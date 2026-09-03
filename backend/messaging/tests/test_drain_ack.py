import base64
import uuid

import pytest

from messaging.models import QueuedEnvelope

from .conftest import SMALLEST_BUCKET, make_device

DRAIN_URL = "/api/v1/me/envelopes"
ACK_URL = "/api/v1/me/envelopes/ack"


def enqueue(device, count, start=1):
    return [
        QueuedEnvelope.objects.create(
            recipient_device=device, seq=start + i, blob=bytes([97 + i]) * SMALLEST_BUCKET
        )
        for i in range(count)
    ]


@pytest.mark.django_db
def test_a_device_drains_its_own_mailbox_in_seq_order(
    api, active_user, device, auth_headers
):
    enqueue(device, 3)

    resp = api.get(DRAIN_URL, **auth_headers(active_user, device))

    assert resp.status_code == 200
    body = resp.json()
    assert [e["seq"] for e in body["envelopes"]] == [1, 2, 3]
    assert body["has_more"] is False
    assert base64.b64decode(body["envelopes"][0]["blob"]) == b"a" * SMALLEST_BUCKET


@pytest.mark.django_db
def test_a_device_never_sees_another_devices_mailbox(
    api, active_user, device, auth_headers, bob_devices
):
    enqueue(bob_devices[0], 2)

    resp = api.get(DRAIN_URL, **auth_headers(active_user, device))

    assert resp.json()["envelopes"] == []


@pytest.mark.django_db
def test_limit_pages_and_reports_has_more(api, active_user, device, auth_headers):
    enqueue(device, 5)

    resp = api.get(f"{DRAIN_URL}?limit=2", **auth_headers(active_user, device))

    body = resp.json()
    assert [e["seq"] for e in body["envelopes"]] == [1, 2]
    assert body["has_more"] is True


@pytest.mark.django_db
@pytest.mark.parametrize("raw", ["abc", "-5", "0", "", "1e3", "999999999999999999999999"])
def test_a_hostile_limit_never_500s(api, active_user, device, auth_headers, raw):
    """`int("abc")` raises and a negative limit poisons the slice; both are 500s if
    the cap is applied the obvious way."""
    enqueue(device, 3)

    resp = api.get(f"{DRAIN_URL}?limit={raw}", **auth_headers(active_user, device))

    assert resp.status_code == 200
    assert 1 <= len(resp.json()["envelopes"]) <= 3


@pytest.mark.django_db
def test_the_limit_is_capped_at_one_hundred(api, active_user, device, auth_headers):
    enqueue(device, 3)

    resp = api.get(f"{DRAIN_URL}?limit=100000", **auth_headers(active_user, device))

    assert len(resp.json()["envelopes"]) == 3


@pytest.mark.django_db
def test_ack_deletes_only_the_named_rows(api, active_user, device, auth_headers):
    rows = enqueue(device, 3)

    resp = api.post(
        ACK_URL,
        {"ids": [str(rows[0].id), str(rows[2].id)]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert resp.json() == {"deleted": 2}
    assert list(QueuedEnvelope.objects.values_list("id", flat=True)) == [rows[1].id]


@pytest.mark.django_db
def test_the_drain_surfaces_the_pruned_watermark(api, active_user, device, auth_headers):
    """`pruned_through` is the queue-gap signal: a client whose last acked seq is
    below it lost envelopes to the TTL prune (possibly MLS commits) and must
    trigger a group re-add. Zero means nothing was ever pruned."""
    headers = auth_headers(active_user, device)
    assert api.get(DRAIN_URL, **headers).json()["pruned_through"] == 0

    device.queue_pruned_through = 41  # what a TTL prune pass writes
    device.save(update_fields=["queue_pruned_through"])

    assert api.get(DRAIN_URL, **headers).json()["pruned_through"] == 41


@pytest.mark.django_db
def test_ack_removes_the_row_from_the_database_not_just_the_response(
    api, active_user, device, auth_headers
):
    """Delete-on-ack is a retention guarantee, so the row must be gone from a
    direct table query, not merely filtered out of later drains."""
    row = enqueue(device, 1)[0]
    headers = auth_headers(active_user, device)

    resp = api.post(ACK_URL, {"ids": [str(row.id)]}, format="json", **headers)

    assert resp.json() == {"deleted": 1}
    assert not QueuedEnvelope.objects.filter(id=row.id).exists()
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_ack_is_idempotent(api, active_user, device, auth_headers):
    rows = enqueue(device, 1)
    headers = auth_headers(active_user, device)

    first = api.post(ACK_URL, {"ids": [str(rows[0].id)]}, format="json", **headers)
    second = api.post(ACK_URL, {"ids": [str(rows[0].id)]}, format="json", **headers)

    assert first.json() == {"deleted": 1}
    assert second.json() == {"deleted": 0}


@pytest.mark.django_db
def test_device_a_cannot_ack_device_bs_envelopes(
    api, active_user, device, auth_headers, bob_devices
):
    """IDOR guard: ack is filtered by the calling device, so a valid id from another
    mailbox matches nothing."""
    victim_rows = enqueue(bob_devices[0], 2)

    resp = api.post(
        ACK_URL,
        {"ids": [str(r.id) for r in victim_rows]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert resp.json() == {"deleted": 0}
    assert (
        QueuedEnvelope.objects.filter(recipient_device_id=bob_devices[0].id).count() == 2
    )


@pytest.mark.django_db
def test_a_sibling_device_cannot_ack_its_twins_envelopes(
    api, active_user, device, auth_headers
):
    """Same user, different device: scoping is per device, not per account."""
    sibling = make_device(active_user, 99)
    rows = enqueue(sibling, 1)

    resp = api.post(
        ACK_URL,
        {"ids": [str(rows[0].id)]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert resp.json() == {"deleted": 0}
    assert QueuedEnvelope.objects.filter(recipient_device_id=sibling.id).count() == 1


@pytest.mark.django_db
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
def test_malformed_ack_ids_are_a_400_not_a_500(
    api, active_user, device, auth_headers, ids
):
    """Unparsed, these reach a uuid column and raise Django's ValidationError, which DRF
    does not handle."""
    resp = api.post(
        ACK_URL, {"ids": ids}, format="json", **auth_headers(active_user, device)
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_request"


@pytest.mark.django_db
def test_too_many_ack_ids_is_a_400(api, active_user, device, auth_headers):
    resp = api.post(
        ACK_URL,
        {"ids": [str(uuid.uuid4()) for _ in range(201)]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_request"


@pytest.mark.django_db
def test_a_non_object_ack_body_is_a_400_not_a_500(api, active_user, device, auth_headers):
    """A JSON array body makes request.data a list, whose .get() is an AttributeError."""
    resp = api.post(
        ACK_URL,
        ["not", "an", "object"],
        format="json",
        **auth_headers(active_user, device),
    )

    assert resp.status_code == 400


@pytest.mark.django_db
def test_a_missing_ids_key_acks_nothing(api, active_user, device, auth_headers):
    enqueue(device, 1)

    resp = api.post(ACK_URL, {}, format="json", **auth_headers(active_user, device))

    assert resp.json() == {"deleted": 0}
    assert QueuedEnvelope.objects.count() == 1


@pytest.mark.django_db
@pytest.mark.parametrize("method,url", [("get", DRAIN_URL), ("post", ACK_URL)])
def test_a_register_scope_token_has_no_mailbox(
    api, active_user, auth_headers, method, url
):
    """A register-scope token carries no device, so it cannot reach a mailbox at all."""
    resp = getattr(api, method)(url, **auth_headers(active_user, scope="register"))

    assert resp.status_code == 403


@pytest.mark.django_db
def test_the_drain_response_carries_no_recipient_or_sender_field(
    api, active_user, device, auth_headers
):
    enqueue(device, 1)

    body = api.get(DRAIN_URL, **auth_headers(active_user, device)).json()

    assert set(body["envelopes"][0]) == {"id", "seq", "blob"}
