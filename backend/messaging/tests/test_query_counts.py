"""Query-shape guards for the hot paths.

These lock in the shape, not a micro-benchmark: the drain must stay one indexed query
no matter how full the mailbox is, and the fan-out's device check must stay one query
no matter how many recipients there are.

Counts include the two per-request auth queries `DeviceJWTAuthentication` makes (the
user row and the device row) and, under pytest's per-test transaction, a
SAVEPOINT/RELEASE pair per `atomic()` block. In production, with autocommit, those
savepoints are a real BEGIN/COMMIT instead.
"""
import pytest

from messaging.models import QueuedEnvelope

from .conftest import SMALLEST_BUCKET, envelope_blob, make_device

AUTH_QUERIES = 2

DRAIN_URL = "/api/v1/me/envelopes"
SEND_URL = "/api/v1/envelopes"


def fill(device, count):
    QueuedEnvelope.objects.bulk_create([
        QueuedEnvelope(recipient_device=device, seq=i + 1, blob=b"a" * SMALLEST_BUCKET)
        for i in range(count)
    ])


@pytest.mark.django_db
@pytest.mark.parametrize("mailbox_size", [1, 50, 200])
def test_the_drain_is_one_query_whatever_the_mailbox_holds(
        api, active_user, device, auth_headers, django_assert_num_queries, mailbox_size):
    fill(device, mailbox_size)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1):
        resp = api.get(f"{DRAIN_URL}?limit=100", **headers)

    assert resp.status_code == 200
    assert len(resp.json()["envelopes"]) == min(mailbox_size, 100)


@pytest.mark.django_db
def test_the_liveness_check_is_one_query_however_many_recipients(
        api, active_user, device, auth_headers, bob, django_assert_num_queries):
    """The N+1 that matters: resolving which target devices are live must not become a
    query per recipient. Per accepted recipient the enqueue then costs a fixed 5
    (savepoint, counter update, counter read, insert, release)."""
    targets = [make_device(bob, 200 + i) for i in range(6)]
    headers = auth_headers(active_user, device)
    items = [{"device_id": str(d.id), "blob": envelope_blob(bytes([65 + i]))}
             for i, d in enumerate(targets)]

    with django_assert_num_queries(AUTH_QUERIES + 1 + 5 * len(targets)):
        resp = api.post(SEND_URL, {"messages": items}, format="json", **headers)

    assert resp.json()["accepted"] == 6


@pytest.mark.django_db
def test_a_send_to_only_stale_devices_touches_no_write_query(
        api, active_user, device, auth_headers, bob, django_assert_num_queries):
    """Nothing is enqueued, so nothing beyond the single liveness lookup runs."""
    from django.utils import timezone
    dead = make_device(bob, 300)
    dead.revoked_date = timezone.now().date()
    dead.save(update_fields=["revoked_date"])
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1):
        resp = api.post(SEND_URL, {"messages": [
            {"device_id": str(dead.id), "blob": envelope_blob()}]},
            format="json", **headers)

    assert resp.json()["accepted"] == 0
