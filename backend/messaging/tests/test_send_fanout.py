import base64
import uuid

import pytest
from django.utils import timezone

from messaging import services
from messaging.models import QueuedEnvelope
from messaging.schemas import OutgoingItemIn

from .conftest import envelope_blob

pytestmark = pytest.mark.django_db(transaction=True)

SEND_URL = "/api/v1/envelopes"


def send(http, headers, items):
    return http.post(SEND_URL, json={"messages": items}, headers=headers)


def test_one_message_to_three_devices_becomes_three_independent_rows(
    http, active_user, device, bearer, bob_devices, carol_device
):
    targets = [*bob_devices, carol_device]
    # A real client encrypts separately per recipient device, so the copies differ.
    items = [
        {"device_id": str(d.id), "blob": envelope_blob(bytes([65 + i]))}
        for i, d in enumerate(targets)
    ]

    resp = send(http, bearer(active_user, device), items)

    assert resp.status_code == 202
    assert resp.json() == {"accepted": 3, "stale_devices": []}
    rows = QueuedEnvelope.objects.all()
    assert rows.count() == 3
    # Independent copies: one row per device, no shared row and no shared payload.
    assert {str(r.recipient_device_id) for r in rows} == {str(d.id) for d in targets}
    assert len({bytes(r.blob) for r in rows}) == 3
    # Each device is its own ordering domain, so all three start at 1.
    assert [r.seq for r in rows] == [1, 1, 1]


def test_each_device_gets_its_own_ascending_seq(
    http, active_user, device, bearer, bob_devices
):
    target = bob_devices[0]
    items = [
        {"device_id": str(target.id), "blob": envelope_blob(bytes([97 + i]))}
        for i in range(3)
    ]

    resp = send(http, bearer(active_user, device), items)

    assert resp.json()["accepted"] == 3
    seqs = list(
        QueuedEnvelope.objects.filter(recipient_device_id=target.id)
        .order_by("seq")
        .values_list("seq", flat=True)
    )
    assert seqs == [1, 2, 3]
    target.refresh_from_db()
    assert target.queue_seq == 3


def test_a_revoked_device_is_reported_stale_and_enqueues_nothing(
    http, active_user, device, bearer, bob_devices
):
    dead, alive = bob_devices
    dead.revoked_date = timezone.now().date()
    dead.save(update_fields=["revoked_date"])

    resp = send(
        http,
        bearer(active_user, device),
        [
            {"device_id": str(dead.id), "blob": envelope_blob()},
            {"device_id": str(alive.id), "blob": envelope_blob(b"b")},
        ],
    )

    assert resp.json() == {"accepted": 1, "stale_devices": [str(dead.id)]}
    assert not QueuedEnvelope.objects.filter(recipient_device_id=dead.id).exists()
    assert QueuedEnvelope.objects.filter(recipient_device_id=alive.id).count() == 1


def test_a_deactivated_users_device_is_stale(
    http, active_user, device, bearer, bob, bob_devices
):
    bob.is_active = False
    bob.save(update_fields=["is_active"])

    resp = send(
        http,
        bearer(active_user, device),
        [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}],
    )

    assert resp.json() == {"accepted": 0, "stale_devices": [str(bob_devices[0].id)]}
    assert QueuedEnvelope.objects.count() == 0


def test_an_unknown_device_is_stale_not_an_error(http, active_user, device, bearer):
    ghost = str(uuid.uuid4())

    resp = send(
        http, bearer(active_user, device), [{"device_id": ghost, "blob": envelope_blob()}]
    )

    assert resp.json() == {"accepted": 0, "stale_devices": [ghost]}


def test_a_rejected_item_queues_nothing_for_the_rest_of_the_batch(
    http, active_user, device, bearer, bob_devices
):
    """A batch that fails on its last item leaves no row from its first: a client
    that retries a rejected batch must not find half of it already queued."""
    good, other = bob_devices
    off_bucket = base64.b64encode(b"a" * 1023).decode()

    resp = send(
        http,
        bearer(active_user, device),
        [
            {"device_id": str(good.id), "blob": envelope_blob()},
            {"device_id": str(other.id), "blob": off_bucket},
        ],
    )

    assert resp.status_code == 400
    assert QueuedEnvelope.objects.count() == 0
    good.refresh_from_db()
    assert good.queue_seq == 0  # the counter did not advance either


def test_a_failed_insert_takes_the_counter_advance_down_with_it(bob_devices, monkeypatch):
    """One send is one transaction, and this is the half validation cannot show.

    The counter advance and the insert are two statements; outside one transaction
    a failed insert would leave the mailbox counter ahead of its rows, and every
    seq it skipped would read to the client as an envelope the TTL prune ate.
    Driven at the unit of work rather than over HTTP, because Starlette re-raises
    after it renders the 500 and the test client would see the exception instead
    of the state left behind.
    """
    target = bob_devices[0]

    def refuse(*args, **kwargs):
        raise RuntimeError("the insert failed")

    monkeypatch.setattr(QueuedEnvelope.objects, "bulk_create", refuse)

    with pytest.raises(RuntimeError):
        services.send(
            [
                OutgoingItemIn(device_id=str(target.id), blob=envelope_blob()),
            ]
        )

    target.refresh_from_db()
    assert target.queue_seq == 0
    assert QueuedEnvelope.objects.count() == 0


def test_an_off_bucket_blob_is_rejected_without_echoing_the_payload(
    http, active_user, device, bearer, bob_devices
):
    off_bucket = base64.b64encode(b"a" * 1023).decode()

    resp = send(
        http,
        bearer(active_user, device),
        [{"device_id": str(bob_devices[0].id), "blob": off_bucket}],
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_bucket"
    assert off_bucket not in resp.text
    assert QueuedEnvelope.objects.count() == 0


def test_a_register_scope_token_cannot_send(
    http, active_user, register_bearer, bob_devices
):
    """A register-scope token's only power is POST /me/devices."""
    resp = send(
        http,
        register_bearer(active_user),
        [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}],
    )

    assert resp.status_code == 403
    assert resp.json()["code"] == "scope_forbidden"
    assert QueuedEnvelope.objects.count() == 0


def test_an_unknown_field_is_rejected(http, active_user, device, bearer, bob_devices):
    resp = http.post(
        SEND_URL,
        json={
            "messages": [
                {
                    "device_id": str(bob_devices[0].id),
                    "blob": envelope_blob(),
                    "sender": "alice",
                }
            ]
        },
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 400
    assert QueuedEnvelope.objects.count() == 0


def test_the_batch_cap_is_enforced(http, active_user, device, bearer, bob_devices):
    items = [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}] * 257

    resp = send(http, bearer(active_user, device), items)

    assert resp.status_code == 400
    assert QueuedEnvelope.objects.count() == 0


def test_anonymous_send_is_rejected(http, bob_devices):
    resp = send(
        http, {}, [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}]
    )

    assert resp.status_code == 401
    assert QueuedEnvelope.objects.count() == 0
