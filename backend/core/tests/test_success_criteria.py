"""Success-criteria aggregator.

Keeps the four headline invariants executable in one place, through the public
surface, so they cannot silently rot when the per-app suites are refactored:

1. no plaintext, no content key, no graph at rest (re-runs the seizure-guard audit);
2. a brand-new device restores the key backup, and no server-side history exists
   for it to restore — history is client-to-client (vault flow);
3. revoking a device cuts its access and destroys its server state (devices flow);
4. fan-out writes one independent row per recipient device and stores no sender
   (messaging proof).
"""

import base64

import pytest

from api.auth import issue_full
from core.buckets import BACKUP_BUCKETS, ENVELOPE_BUCKETS
from core.tests.test_seizure_guard import (
    dual_user_fk_offenders,
    envelope_graph_offenders,
    forbidden_column_offenders,
    raw_binary_offenders,
    unbucketed_blob_offenders,
)
from devices.models import Device
from messaging.models import QueuedEnvelope

pytestmark = pytest.mark.django_db

DEVICES_URL = "/api/v1/me/devices"
KEYBACKUP_URL = "/api/v1/me/keybackup"
ENVELOPES_URL = "/api/v1/envelopes"


def _b64(size, fill):
    return base64.b64encode(bytes([fill]) * size).decode()


def _second_device(user, registration_id):
    return Device.objects.create(
        user=user,
        ik_pub=b"ik2",
        spk_id=2,
        spk_pub=b"spk2",
        spk_sig=b"sig2",
        registration_id=registration_id,
    )


def test_nothing_readable_or_graph_shaped_can_exist_at_rest():
    """Executes the full seizure-guard audit over the live app registry.
    Infrastructure secrets exist and are expected; content keys and graphs may not."""
    for audit in (
        forbidden_column_offenders,
        unbucketed_blob_offenders,
        raw_binary_offenders,
        envelope_graph_offenders,
        dual_user_fk_offenders,
    ):
        assert audit() == [], f"{audit.__name__} found violations"


# transaction=True because the key backup is a FastAPI route now, and the ORM
# bracket behind it closes the connection a wrapping test transaction would need.
@pytest.mark.django_db(transaction=True)
def test_a_new_device_restores_the_backup_and_no_server_history_exists(
    http, active_user, device, bearer
):
    """A brand-new device reads the key backup back byte-identical — and that is
    all the server has for it. History is client-to-client on enrollment; the old
    "log in on a new device and your chats are there" flow is superseded, and the
    server-side half of it must stay gone (vault/tests/test_no_history.py pins the
    full removal)."""
    first = bearer(active_user, device)
    backup = _b64(min(BACKUP_BUCKETS), 0x4B)

    assert (
        http.put(
            KEYBACKUP_URL, json={"blob": backup, "version": 1}, headers=first
        ).status_code
        == 200
    )

    fresh = bearer(active_user, _second_device(active_user, 9001))
    assert http.get(KEYBACKUP_URL, headers=fresh).json() == {
        "blob": backup,
        "version": 1,
    }
    assert http.get("/api/v1/me/history", headers=fresh).status_code == 404


def test_revoking_a_device_cuts_its_access_and_destroys_its_state(
    api, active_user, device, auth_headers
):
    """After DELETE, the revoked device's tokens die and its queue is gone (the full
    cascade and ETag behaviour live in devices/tests/test_revocation.py)."""
    doomed = _second_device(active_user, 9002)
    doomed_access, _ = issue_full(active_user, doomed)
    QueuedEnvelope.objects.create(
        recipient_device=doomed, seq=1, blob=b"\xa5" * min(ENVELOPE_BUCKETS)
    )
    doomed_headers = {"HTTP_AUTHORIZATION": f"Bearer {doomed_access}"}
    assert api.get(DEVICES_URL, **doomed_headers).status_code == 200

    assert (
        api.delete(
            f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device)
        ).status_code
        == 204
    )

    assert api.get(DEVICES_URL, **doomed_headers).status_code == 401
    assert QueuedEnvelope.objects.filter(recipient_device=doomed).count() == 0


def test_fanout_writes_independent_copies_and_never_a_sender(
    api, active_user, device, auth_headers
):
    """No-graph fan-out: N targets become N independent rows, each knowing only its
    recipient device; the sender appears in no stored value (messaging/tests/
    test_send_fanout.py and test_at_rest.py prove the full property)."""
    from accounts.models import User

    bob = User.objects.create_user(
        username="bob", password="x-trellis-9-quartz", is_active=True
    )
    targets = [_second_device(bob, 9003), _second_device(bob, 9004)]
    blob = _b64(min(ENVELOPE_BUCKETS), 0x5A)

    resp = api.post(
        ENVELOPES_URL,
        {"messages": [{"device_id": str(d.id), "blob": blob} for d in targets]},
        format="json",
        **auth_headers(active_user, device),
    )
    assert resp.status_code == 202

    rows = list(QueuedEnvelope.objects.order_by("seq"))
    assert len(rows) == 2
    assert len({row.id for row in rows}) == 2, "copies must be independent rows"
    assert {row.recipient_device_id for row in rows} == {d.id for d in targets}
    sender_traces = {str(active_user.id), str(device.id)}
    for row in rows:
        stored = {
            str(value)
            for value in (row.id, row.recipient_device_id, row.seq, row.queued_hour)
        }
        assert stored & sender_traces == set(), "a stored value identifies the sender"
