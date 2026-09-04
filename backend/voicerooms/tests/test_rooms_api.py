"""Room CRUD: create/read/rename an id plus encrypted-name row, nothing else."""

import base64
import uuid
from datetime import date

import pytest
import redis
from django.conf import settings
from django.utils import timezone

from core.buckets import NAME_BUCKETS
from voicerooms.models import Room
from voicerooms.presence import _key

from .conftest import DEAD_REDIS_URL, NAME_LEN, name_blob_b64

# transaction=True because every route runs its unit of work through the ORM
# bracket of `api.orm.run_unit`, which closes the connection a wrapping test
# transaction would need.
pytestmark = pytest.mark.django_db(transaction=True)

ROOMS_URL = "/api/v1/rooms"


def test_create_returns_the_capability_id_and_stores_one_bucketed_blob(
    http, active_user, device, bearer
):
    resp = http.post(
        ROOMS_URL,
        json={"name_blob": name_blob_b64(b"q")},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 201
    room = Room.objects.get(id=resp.json()["room_id"])
    assert bytes(room.name_blob) == b"q" * NAME_LEN


def test_an_unknown_field_is_rejected(http, active_user, device, bearer):
    resp = http.post(
        ROOMS_URL,
        json={"name_blob": name_blob_b64(b"q"), "junk": 1},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "junk" in resp.json()["detail"]


def test_get_round_trips_the_blob_and_reports_zero_live(
    http, active_user, device, bearer, room
):
    resp = http.get(f"{ROOMS_URL}/{room.id}", headers=bearer(active_user, device))

    assert resp.status_code == 200
    assert resp.json() == {
        "room_id": str(room.id),
        "name_blob": base64.b64encode(b"n" * NAME_LEN).decode(),
        "updated_date": timezone.now().date().isoformat(),
        "live_count": 0,
    }


def test_rename_changes_the_blob_and_bumps_updated_date(
    http, active_user, device, bearer, room
):
    # Predate the row so the bump is observable: auto_now never fires on a queryset
    # .update(), which is exactly why the service sets updated_date explicitly.
    Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))

    resp = http.put(
        f"{ROOMS_URL}/{room.id}",
        json={"name_blob": name_blob_b64(b"z")},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 200
    assert resp.content == b""
    room.refresh_from_db()
    assert bytes(room.name_blob) == b"z" * NAME_LEN
    assert room.updated_date == timezone.now().date()


def test_unknown_room_is_404_for_get_and_put(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    missing = uuid.uuid4()

    read = http.get(f"{ROOMS_URL}/{missing}", headers=headers)
    renamed = http.put(
        f"{ROOMS_URL}/{missing}", json={"name_blob": name_blob_b64()}, headers=headers
    )

    for resp in (read, renamed):
        assert resp.status_code == 404
        assert resp.json() == {"code": "not_found", "detail": "No such room."}


def test_a_malformed_room_id_is_an_invalid_request(http, active_user, device, bearer):
    """A path segment that is not a UUID is a client defect, not a missing room."""
    resp = http.get(f"{ROOMS_URL}/not-a-uuid", headers=bearer(active_user, device))

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "room_id" in resp.json()["detail"]


@pytest.mark.parametrize(
    "bad",
    [
        base64.b64encode(b"x" * 100).decode(),  # not a bucket length
        "@@@not-base64@@@",  # not base64 at all
    ],
)
def test_off_bucket_names_are_rejected_without_echo(
    http, active_user, device, bearer, room, bad
):
    headers = bearer(active_user, device)
    for verb, url in (("PUT", f"{ROOMS_URL}/{room.id}"), ("POST", ROOMS_URL)):
        resp = http.request(verb, url, json={"name_blob": bad}, headers=headers)

        assert resp.status_code == 400
        assert resp.json() == {"code": "bad_bucket", "detail": "Invalid payload."}
        assert bad not in resp.text


def test_missing_name_blob_is_an_invalid_request(http, active_user, device, bearer):
    resp = http.post(ROOMS_URL, json={}, headers=bearer(active_user, device))

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "name_blob" in resp.json()["detail"]


def test_register_scope_tokens_are_locked_out_of_every_room_endpoint(
    http, active_user, register_bearer, room
):
    """A register-scope token's only power is POST /me/devices; a requirement that
    only checked identity would have admitted one here."""
    headers = register_bearer(active_user)
    name = {"name_blob": name_blob_b64()}

    assert http.post(ROOMS_URL, json=name, headers=headers).status_code == 403
    assert http.get(f"{ROOMS_URL}/{room.id}", headers=headers).status_code == 403
    assert (
        http.put(f"{ROOMS_URL}/{room.id}", json=name, headers=headers).status_code == 403
    )
    assert http.post(f"{ROOMS_URL}/{room.id}/token", headers=headers).status_code == 403


def test_anonymous_requests_are_401(http, room):
    assert http.post(ROOMS_URL, json={"name_blob": name_blob_b64()}).status_code == 401
    assert http.get(f"{ROOMS_URL}/{room.id}").status_code == 401
    assert http.post(f"{ROOMS_URL}/{room.id}/token").status_code == 401


@pytest.fixture
def store():
    """A synchronous client for the presence sets, because these tests drive the
    surface synchronously; the gateway writes the same sets from its own loop."""
    client = redis.Redis.from_url(settings.REDIS_URL)
    yield client
    client.close()


@pytest.mark.parametrize("bucket", NAME_BUCKETS)
def test_a_name_of_either_bucket_is_created_and_read_back_unchanged(
    http, active_user, device, bearer, bucket
):
    """The boundary of the accepted set, end to end: both declared lengths make a
    room, and the blob a client reads is the blob it wrote."""
    headers = bearer(active_user, device)
    blob = base64.b64encode(b"k" * bucket).decode()

    created = http.post(ROOMS_URL, json={"name_blob": blob}, headers=headers)
    read = http.get(f"{ROOMS_URL}/{created.json()['room_id']}", headers=headers)

    assert created.status_code == 201
    assert read.json()["name_blob"] == blob


def test_every_successful_rename_moves_the_updated_date_forward(
    http, active_user, device, bearer, room
):
    """`updated_date` is the whole rename notification: a peer polling `GET` has
    nothing else to notice a change by, so every accepted rename has to move it —
    including the second and third one on the same room."""
    headers = bearer(active_user, device)
    today = timezone.now().date()

    for filler in (b"1", b"2", b"3"):
        Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))

        resp = http.put(
            f"{ROOMS_URL}/{room.id}",
            json={"name_blob": name_blob_b64(filler)},
            headers=headers,
        )

        assert resp.status_code == 200
        room.refresh_from_db()
        assert bytes(room.name_blob) == filler * NAME_LEN
        assert room.updated_date == today


def test_a_rename_of_an_unknown_room_writes_nothing_at_all(
    http, active_user, device, bearer, room
):
    """The error path that must not become a create: a `404` leaves the table
    exactly as it was, with no row under the id the client chose."""
    Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))
    missing = uuid.uuid4()

    resp = http.put(
        f"{ROOMS_URL}/{missing}",
        json={"name_blob": name_blob_b64(b"x")},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 404
    assert not Room.objects.filter(id=missing).exists()
    assert Room.objects.count() == 1
    room.refresh_from_db()
    assert bytes(room.name_blob) == b"n" * NAME_LEN
    assert room.updated_date == date(2020, 1, 1)


def test_the_live_count_is_the_size_of_the_redis_set_and_nothing_else(
    http, active_user, device, bearer, room, store
):
    """The only field of the read that is not a column. It comes from the set the
    gateway maintains, so a room with two devices in it reads two — and the number
    falls back to zero the moment the set is gone."""
    headers = bearer(active_user, device)
    store.sadd(_key(room.id), "device-a", "device-b")

    assert http.get(f"{ROOMS_URL}/{room.id}", headers=headers).json()["live_count"] == 2

    store.delete(_key(room.id))

    assert http.get(f"{ROOMS_URL}/{room.id}", headers=headers).json()["live_count"] == 0


@pytest.mark.parametrize(
    "method, body",
    [
        ("GET", None),
        ("POST", {"name_blob": name_blob_b64()}),
        ("PUT", {"name_blob": name_blob_b64()}),
    ],
)
def test_an_unreachable_redis_fails_closed_before_any_room_is_touched(
    http, active_user, device, bearer, room, settings, method, body
):
    """The rate limiter shares the presence client and fails closed, so an outage
    is a `503` the client retries rather than a wrong `live_count` or a `500`. The
    read is the one that matters: without the limiter in front of it, the count
    would either raise or quietly report an empty room."""
    settings.REDIS_URL = DEAD_REDIS_URL
    url = ROOMS_URL if method == "POST" else f"{ROOMS_URL}/{room.id}"

    resp = http.request(method, url, json=body, headers=bearer(active_user, device))

    assert resp.status_code == 503
    assert resp.json() == {
        "code": "unavailable",
        "detail": "The service is temporarily unavailable.",
    }


def test_an_unreachable_redis_leaves_the_room_untouched(
    http, active_user, device, bearer, room, settings
):
    """The other half of failing closed: the refusal happens before the unit of
    work, so a rename refused this way stored nothing."""
    Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))
    settings.REDIS_URL = DEAD_REDIS_URL

    http.put(
        f"{ROOMS_URL}/{room.id}",
        json={"name_blob": name_blob_b64(b"z")},
        headers=bearer(active_user, device),
    )

    room.refresh_from_db()
    assert bytes(room.name_blob) == b"n" * NAME_LEN
    assert room.updated_date == date(2020, 1, 1)


def test_every_room_response_forbids_a_cache_from_keeping_it(
    http, active_user, device, bearer, room, voice_settings
):
    """A room answer carries an encrypted name or a join grant, so no shared cache
    may hold one and no referrer may carry the capability out of the page."""
    headers = bearer(active_user, device)

    for resp in (
        http.get(f"{ROOMS_URL}/{room.id}", headers=headers),
        http.post(f"{ROOMS_URL}/{room.id}/token", headers=headers),
        http.post(ROOMS_URL, json={"name_blob": name_blob_b64()}, headers=headers),
    ):
        assert resp.headers["cache-control"] == "no-store"
        assert resp.headers["referrer-policy"] == "no-referrer"
        assert resp.headers["x-content-type-options"] == "nosniff"
