import base64
import uuid

import pytest
from django.utils import timezone

from messaging.models import QueuedEnvelope

from .conftest import envelope_blob

SEND_URL = "/api/v1/envelopes"


def send(api, headers, items):
    return api.post(SEND_URL, {"messages": items}, format="json", **headers)


@pytest.mark.django_db
def test_one_message_to_three_devices_becomes_three_independent_rows(
        api, active_user, device, auth_headers, bob_devices, carol_device):
    targets = [*bob_devices, carol_device]
    # A real client encrypts separately per recipient device, so the copies differ.
    items = [{"device_id": str(d.id), "blob": envelope_blob(bytes([65 + i]))}
             for i, d in enumerate(targets)]

    resp = send(api, auth_headers(active_user, device), items)

    assert resp.status_code == 202
    assert resp.json() == {"accepted": 3, "stale_devices": []}
    rows = QueuedEnvelope.objects.all()
    assert rows.count() == 3
    # Independent copies: one row per device, no shared row and no shared payload.
    assert {str(r.recipient_device_id) for r in rows} == {str(d.id) for d in targets}
    assert len({bytes(r.blob) for r in rows}) == 3
    # Each device is its own ordering domain, so all three start at 1.
    assert [r.seq for r in rows] == [1, 1, 1]


@pytest.mark.django_db
def test_each_device_gets_its_own_ascending_seq(api, active_user, device, auth_headers,
                                                bob_devices):
    target = bob_devices[0]
    items = [{"device_id": str(target.id), "blob": envelope_blob(bytes([97 + i]))}
             for i in range(3)]

    resp = send(api, auth_headers(active_user, device), items)

    assert resp.json()["accepted"] == 3
    seqs = list(QueuedEnvelope.objects.filter(recipient_device_id=target.id)
                .order_by("seq").values_list("seq", flat=True))
    assert seqs == [1, 2, 3]
    target.refresh_from_db()
    assert target.queue_seq == 3


@pytest.mark.django_db
def test_a_revoked_device_is_reported_stale_and_enqueues_nothing(
        api, active_user, device, auth_headers, bob_devices):
    dead, alive = bob_devices
    dead.revoked_date = timezone.now().date()
    dead.save(update_fields=["revoked_date"])

    resp = send(api, auth_headers(active_user, device), [
        {"device_id": str(dead.id), "blob": envelope_blob()},
        {"device_id": str(alive.id), "blob": envelope_blob(b"b")},
    ])

    assert resp.json() == {"accepted": 1, "stale_devices": [str(dead.id)]}
    assert not QueuedEnvelope.objects.filter(recipient_device_id=dead.id).exists()
    assert QueuedEnvelope.objects.filter(recipient_device_id=alive.id).count() == 1


@pytest.mark.django_db
def test_a_deactivated_users_device_is_stale(api, active_user, device, auth_headers,
                                             bob, bob_devices):
    bob.is_active = False
    bob.save(update_fields=["is_active"])

    resp = send(api, auth_headers(active_user, device),
                [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}])

    assert resp.json() == {"accepted": 0, "stale_devices": [str(bob_devices[0].id)]}
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_an_unknown_device_is_stale_not_an_error(api, active_user, device, auth_headers):
    ghost = str(uuid.uuid4())

    resp = send(api, auth_headers(active_user, device),
                [{"device_id": ghost, "blob": envelope_blob()}])

    assert resp.json() == {"accepted": 0, "stale_devices": [ghost]}


@pytest.mark.django_db
def test_an_off_bucket_blob_is_rejected_without_echoing_the_payload(
        api, active_user, device, auth_headers, bob_devices):
    off_bucket = base64.b64encode(b"a" * 1023).decode()

    resp = send(api, auth_headers(active_user, device),
                [{"device_id": str(bob_devices[0].id), "blob": off_bucket}])

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_bucket"
    assert off_bucket not in resp.content.decode()
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_a_register_scope_token_cannot_send(api, active_user, auth_headers, bob_devices):
    """A register-scope token's only power is POST /me/devices."""
    resp = send(api, auth_headers(active_user, scope="register"),
                [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}])

    assert resp.status_code == 403
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_an_unknown_field_is_rejected(api, active_user, device, auth_headers, bob_devices):
    resp = api.post(SEND_URL, {"messages": [{"device_id": str(bob_devices[0].id),
                                             "blob": envelope_blob(),
                                             "sender": "alice"}]},
                    format="json", **auth_headers(active_user, device))

    assert resp.status_code == 400
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_the_batch_cap_is_enforced(api, active_user, device, auth_headers, bob_devices):
    items = [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}] * 257

    resp = send(api, auth_headers(active_user, device), items)

    assert resp.status_code == 400
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_anonymous_send_is_rejected(api, bob_devices):
    resp = send(api, {}, [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}])

    assert resp.status_code == 401
    assert QueuedEnvelope.objects.count() == 0
