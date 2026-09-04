import base64
import uuid

import pytest

from messaging.models import QueuedEnvelope

from .conftest import SMALLEST_BUCKET, make_device

pytestmark = pytest.mark.django_db(transaction=True)

DRAIN_URL = "/api/v1/me/envelopes"
ACK_URL = "/api/v1/me/envelopes/ack"


def enqueue(device, count, start=1):
    return [
        QueuedEnvelope.objects.create(
            recipient_device=device, seq=start + i, blob=bytes([97 + i]) * SMALLEST_BUCKET
        )
        for i in range(count)
    ]


def test_a_device_drains_its_own_mailbox_in_seq_order(http, active_user, device, bearer):
    enqueue(device, 3)

    resp = http.get(DRAIN_URL, headers=bearer(active_user, device))

    assert resp.status_code == 200
    body = resp.json()
    assert [e["seq"] for e in body["envelopes"]] == [1, 2, 3]
    assert body["has_more"] is False
    assert base64.b64decode(body["envelopes"][0]["blob"]) == b"a" * SMALLEST_BUCKET


def test_a_device_never_sees_another_devices_mailbox(
    http, active_user, device, bearer, bob_devices
):
    enqueue(bob_devices[0], 2)

    resp = http.get(DRAIN_URL, headers=bearer(active_user, device))

    assert resp.json()["envelopes"] == []


def test_limit_pages_and_reports_has_more(http, active_user, device, bearer):
    enqueue(device, 5)

    resp = http.get(f"{DRAIN_URL}?limit=2", headers=bearer(active_user, device))

    body = resp.json()
    assert [e["seq"] for e in body["envelopes"]] == [1, 2]
    assert body["has_more"] is True


@pytest.mark.parametrize("raw", ["abc", "-5", "0", "", "1e3", "999999999999999999999999"])
def test_a_hostile_limit_never_500s(http, active_user, device, bearer, raw):
    """`int("abc")` raises and a negative limit poisons the slice; both are 500s if
    the cap is applied the obvious way, and both are 400s if the parameter is
    declared as an integer, which this route's contract forbids."""
    enqueue(device, 3)

    resp = http.get(f"{DRAIN_URL}?limit={raw}", headers=bearer(active_user, device))

    assert resp.status_code == 200
    assert 1 <= len(resp.json()["envelopes"]) <= 3


def test_the_limit_is_capped_at_one_hundred(http, active_user, device, bearer):
    enqueue(device, 3)

    resp = http.get(f"{DRAIN_URL}?limit=100000", headers=bearer(active_user, device))

    assert len(resp.json()["envelopes"]) == 3


def test_ack_deletes_only_the_named_rows(http, active_user, device, bearer):
    rows = enqueue(device, 3)

    resp = http.post(
        ACK_URL,
        json={"ids": [str(rows[0].id), str(rows[2].id)]},
        headers=bearer(active_user, device),
    )

    assert resp.json() == {"deleted": 2}
    assert list(QueuedEnvelope.objects.values_list("id", flat=True)) == [rows[1].id]


def test_the_drain_surfaces_the_pruned_watermark(http, active_user, device, bearer):
    """`pruned_through` is the queue-gap signal: a client whose last acked seq is
    below it lost envelopes to the TTL prune (possibly ratchet messages or control
    events) and must repair the affected pairwise sessions. Zero means nothing was
    ever pruned."""
    headers = bearer(active_user, device)
    assert http.get(DRAIN_URL, headers=headers).json()["pruned_through"] == 0

    device.queue_pruned_through = 41  # what a TTL prune pass writes
    device.save(update_fields=["queue_pruned_through"])

    assert http.get(DRAIN_URL, headers=headers).json()["pruned_through"] == 41


def test_ack_removes_the_row_from_the_database_not_just_the_response(
    http, active_user, device, bearer
):
    """Delete-on-ack is a retention guarantee, so the row must be gone from a
    direct table query, not merely filtered out of later drains."""
    row = enqueue(device, 1)[0]

    resp = http.post(
        ACK_URL, json={"ids": [str(row.id)]}, headers=bearer(active_user, device)
    )

    assert resp.json() == {"deleted": 1}
    assert not QueuedEnvelope.objects.filter(id=row.id).exists()
    assert QueuedEnvelope.objects.count() == 0


def test_ack_is_idempotent(http, active_user, device, bearer):
    rows = enqueue(device, 1)
    headers = bearer(active_user, device)

    first = http.post(ACK_URL, json={"ids": [str(rows[0].id)]}, headers=headers)
    second = http.post(ACK_URL, json={"ids": [str(rows[0].id)]}, headers=headers)

    assert first.json() == {"deleted": 1}
    assert second.json() == {"deleted": 0}


def test_device_a_cannot_ack_device_bs_envelopes(
    http, active_user, device, bearer, bob_devices
):
    """IDOR guard: ack is filtered by the calling device, so a valid id from another
    mailbox matches nothing."""
    victim_rows = enqueue(bob_devices[0], 2)

    resp = http.post(
        ACK_URL,
        json={"ids": [str(r.id) for r in victim_rows]},
        headers=bearer(active_user, device),
    )

    assert resp.json() == {"deleted": 0}
    assert (
        QueuedEnvelope.objects.filter(recipient_device_id=bob_devices[0].id).count() == 2
    )


def test_a_sibling_device_cannot_ack_its_twins_envelopes(
    http, active_user, device, bearer
):
    """Same user, different device: scoping is per device, not per account."""
    sibling = make_device(active_user, 99)
    rows = enqueue(sibling, 1)

    resp = http.post(
        ACK_URL, json={"ids": [str(rows[0].id)]}, headers=bearer(active_user, device)
    )

    assert resp.json() == {"deleted": 0}
    assert QueuedEnvelope.objects.filter(recipient_device_id=sibling.id).count() == 1


@pytest.mark.parametrize(
    "ids",
    [
        ["abc"],
        [123],
        [None],
        [{}],
        ["../../etc/passwd"],
        [str(uuid.uuid4()), "not-a-uuid"],
    ],
)
def test_malformed_ack_ids_are_a_400_not_a_500(http, active_user, device, bearer, ids):
    """Unparsed, these reach a uuid column and raise Django's ValidationError, which
    nothing below the route turns into anything but a 500."""
    resp = http.post(ACK_URL, json={"ids": ids}, headers=bearer(active_user, device))

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"


def test_too_many_ack_ids_is_a_400(http, active_user, device, bearer):
    resp = http.post(
        ACK_URL,
        json={"ids": [str(uuid.uuid4()) for _ in range(201)]},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"


def test_a_non_object_ack_body_is_a_400_not_a_500(http, active_user, device, bearer):
    """A JSON array body is not a mapping, and reading `ids` off one is an
    AttributeError."""
    resp = http.post(
        ACK_URL, json=["not", "an", "object"], headers=bearer(active_user, device)
    )

    assert resp.status_code == 400


def test_a_missing_ids_key_acks_nothing(http, active_user, device, bearer):
    enqueue(device, 1)

    resp = http.post(ACK_URL, json={}, headers=bearer(active_user, device))

    assert resp.json() == {"deleted": 0}
    assert QueuedEnvelope.objects.count() == 1


@pytest.mark.parametrize("method,url", [("get", DRAIN_URL), ("post", ACK_URL)])
def test_a_register_scope_token_has_no_mailbox(
    http, active_user, register_bearer, method, url
):
    """A register-scope token carries no device, so it cannot reach a mailbox at all."""
    headers = register_bearer(active_user)
    resp = (
        http.post(url, json={}, headers=headers)
        if method == "post"
        else http.get(url, headers=headers)
    )

    assert resp.status_code == 403
    assert resp.json()["code"] == "scope_forbidden"


def test_the_drain_response_carries_no_recipient_or_sender_field(
    http, active_user, device, bearer
):
    enqueue(device, 1)

    body = http.get(DRAIN_URL, headers=bearer(active_user, device)).json()

    assert set(body["envelopes"][0]) == {"id", "seq", "blob"}
