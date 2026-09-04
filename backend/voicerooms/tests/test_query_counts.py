"""Query-shape guards for the voice-room routes.

A room is a capability id and an encrypted name, and live participation is Redis
alone, so every route here is the authentication plus at most one statement. What
this pins is that it stays that way: a membership table or an owner column would
show up here as a second query before it showed up anywhere else.

Counted end to end through the composed application, so each number includes the
one query the authentication dependency makes: the device row joined to its
owner. `transaction=True` makes the transaction statements real BEGIN/COMMIT
rather than savepoints, and they are excluded here so the number is the database
work itself.
"""

import uuid

import pytest
import redis
from django.conf import settings
from django.db import connection
from django.test.utils import CaptureQueriesContext

from voicerooms.models import Room
from voicerooms.presence import _key

from .conftest import name_blob_b64

pytestmark = pytest.mark.django_db(transaction=True)

TRANSACTION_STATEMENTS = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE", "ROLLBACK")

AUTH_QUERY = 1  # the device row, joined to its owner

ROOMS_URL = "/api/v1/rooms"
# Over 32 bytes, so signing the grant raises no key-length warning.
SECRET = "lk-test-secret-well-over-thirty-two-bytes-long"


def counted(http, method, url, expected, **kwargs):
    with CaptureQueriesContext(connection) as context:
        response = http.request(method, url, **kwargs)
    sqls = [
        query["sql"]
        for query in context.captured_queries
        if not query["sql"].startswith(TRANSACTION_STATEMENTS)
    ]
    assert len(sqls) == expected, "\n".join(sqls)
    return response


def test_creating_a_room_is_one_insert(http, active_user, device, bearer):
    response = counted(
        http,
        "POST",
        ROOMS_URL,
        AUTH_QUERY + 1,
        json={"name_blob": name_blob_b64()},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 201


@pytest.mark.parametrize("room_count", [1, 25])
def test_reading_a_room_is_one_lookup_however_many_rooms_exist(
    http, active_user, device, bearer, room, room_count
):
    """The live count comes from Redis, not from a column and not from a join, so
    it must add no query at all."""
    Room.objects.bulk_create([Room(name_blob=b"n" * 256) for _ in range(room_count - 1)])

    response = counted(
        http,
        "GET",
        f"{ROOMS_URL}/{room.id}",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.json()["live_count"] == 0


def test_renaming_a_room_is_one_update(http, active_user, device, bearer, room):
    """The ownership question does not exist here — the id is the capability — so
    the rename must not read the row before writing it."""
    response = counted(
        http,
        "PUT",
        f"{ROOMS_URL}/{room.id}",
        AUTH_QUERY + 1,
        json={"name_blob": name_blob_b64(b"m")},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200


def test_minting_a_join_token_is_one_existence_check(
    http, active_user, device, bearer, room, settings
):
    """The grant is signed from the room id and the calling device, both already in
    hand, so the only query is the one that proves the room is real."""
    settings.LIVEKIT_URL = "wss://voice.test"
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET

    response = counted(
        http,
        "POST",
        f"{ROOMS_URL}/{room.id}/token",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200


@pytest.fixture
def store():
    client = redis.Redis.from_url(settings.REDIS_URL)
    yield client
    client.close()


def test_a_room_with_people_in_it_costs_no_more_than_an_empty_one(
    http, active_user, device, bearer, room, store
):
    """The live count is a Redis read, so a busy room must cost exactly what a
    quiet one does. A count that had become a column or a join would show up here
    as an extra statement before it showed up as a slow page."""
    store.sadd(_key(room.id), "device-a", "device-b", "device-c")

    response = counted(
        http,
        "GET",
        f"{ROOMS_URL}/{room.id}",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.json()["live_count"] == 3


def test_reading_a_room_that_does_not_exist_is_one_lookup_and_no_more(
    http, active_user, device, bearer
):
    """The error path costs the same as the normal one: the refusal comes from the
    single lookup, not from a second query asking why it was empty."""
    response = counted(
        http,
        "GET",
        f"{ROOMS_URL}/{uuid.uuid4()}",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.status_code == 404


def test_renaming_a_room_that_does_not_exist_is_one_update_and_no_more(
    http, active_user, device, bearer
):
    """The `404` is read off the row count the `UPDATE` returns, so proving the
    room is missing must not cost a `SELECT` of its own."""
    response = counted(
        http,
        "PUT",
        f"{ROOMS_URL}/{uuid.uuid4()}",
        AUTH_QUERY + 1,
        json={"name_blob": name_blob_b64()},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 404


def test_minting_against_an_unknown_room_stops_at_the_existence_check(
    http, active_user, device, bearer, settings
):
    settings.LIVEKIT_URL = "wss://voice.test"
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET

    response = counted(
        http,
        "POST",
        f"{ROOMS_URL}/{uuid.uuid4()}/token",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.status_code == 404


@pytest.mark.parametrize(
    "body", [{"name_blob": "!!!!"}, {"name_blob": ""}, {"owner": "alice"}, []]
)
def test_a_body_the_surface_refuses_never_reaches_the_database(
    http, active_user, device, bearer, body
):
    """Validation runs before the unit of work, so a hostile body costs the
    authentication query and nothing else — which is what keeps a flood of
    malformed requests off the connection pool."""
    response = counted(
        http,
        "POST",
        ROOMS_URL,
        AUTH_QUERY,
        json=body,
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400
