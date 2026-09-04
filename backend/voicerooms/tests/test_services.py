"""The four units of work behind the room routes, driven without a request.

Called directly rather than through HTTP, so what is asserted here is each unit's
own contract: the row it leaves, the bytes it stores, and the `ApiError` it
raises. The route's rendering of those errors is
`voicerooms/tests/test_routes.py`, and the query each one costs is
`voicerooms/tests/test_query_counts.py`.

Two of these units are the whole of the design's access control, which is to say
there is none: `read` and `rename` are keyed on the id alone, because the id is
the capability. A unit here that grew an owner argument would be the moment this
server started holding membership.
"""

import base64
import datetime
import uuid

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from api.errors import ApiError
from core.buckets import NAME_BUCKETS
from voicerooms import services
from voicerooms.models import Room

from .conftest import NAME_LEN

pytestmark = pytest.mark.django_db(transaction=True)

PREDATED = datetime.date(2020, 1, 1)


def predate(room_id):
    """Push `updated_date` into the past, so a bump to today is observable. A row
    written today would read the same either way."""
    Room.objects.filter(id=room_id).update(updated_date=PREDATED)


def test_create_leaves_one_row_holding_exactly_the_bytes_it_was_given():
    result = services.create(b"C" * NAME_LEN)

    room = Room.objects.get(id=result["room_id"])
    assert bytes(room.name_blob) == b"C" * NAME_LEN
    assert Room.objects.count() == 1


def test_create_answers_the_new_capability_as_a_string_and_nothing_else():
    """The route hands this dict straight to `RoomCreatedOut`; a second key here
    would be a second fact about the room the response never promised."""
    result = services.create(b"C" * NAME_LEN)

    assert set(result) == {"room_id"}
    assert result["room_id"] == str(uuid.UUID(result["room_id"]))


def test_read_answers_the_three_stored_facts_base64_encoded():
    """The live count is deliberately not here: it lives in Redis and is read on
    the event loop, so a fourth key would mean this unit had started blocking on
    a socket from the ORM thread."""
    room = Room.objects.create(name_blob=b"R" * NAME_LEN)
    predate(room.id)

    result = services.read(room.id)

    assert result == {
        "room_id": str(room.id),
        "name_blob": base64.b64encode(b"R" * NAME_LEN).decode(),
        "updated_date": PREDATED.isoformat(),
    }


def test_read_of_a_room_that_does_not_exist_raises_the_documented_404():
    with pytest.raises(ApiError) as caught:
        services.read(uuid.uuid4())

    assert caught.value.status_code == 404
    assert caught.value.code == "not_found"
    assert caught.value.detail == "No such room."


def test_rename_replaces_the_blob_and_bumps_the_updated_date():
    room = Room.objects.create(name_blob=b"A" * NAME_LEN)
    predate(room.id)

    services.rename(room.id, b"B" * NAME_LEN)

    room.refresh_from_db()
    assert bytes(room.name_blob) == b"B" * NAME_LEN
    assert room.updated_date == datetime.date.today()


def test_rename_bumps_the_date_even_when_the_name_is_unchanged():
    """`PUT` is idempotent in what it stores, not in what it announces: a peer
    polling `GET` learns that a rename happened from the date alone, so a repeat
    of the same blob still has to move it."""
    room = Room.objects.create(name_blob=b"S" * NAME_LEN)
    predate(room.id)

    services.rename(room.id, b"S" * NAME_LEN)

    room.refresh_from_db()
    assert room.updated_date == datetime.date.today()


def test_rename_of_a_room_that_does_not_exist_raises_404_and_writes_nothing():
    """The error path that must not become a create: an unknown id is a refusal,
    never an insert under an id the caller chose."""
    other = Room.objects.create(name_blob=b"O" * NAME_LEN)
    predate(other.id)

    with pytest.raises(ApiError) as caught:
        services.rename(uuid.uuid4(), b"X" * NAME_LEN)

    assert caught.value.status_code == 404
    assert caught.value.code == "not_found"
    assert Room.objects.count() == 1
    other.refresh_from_db()
    assert bytes(other.name_blob) == b"O" * NAME_LEN
    assert other.updated_date == PREDATED


def test_rename_touches_only_the_room_it_names():
    """The rare case a queryset `.update()` gets wrong: a filter that matched more
    than one row would rename every room in the table at once."""
    target = Room.objects.create(name_blob=b"T" * NAME_LEN)
    bystander = Room.objects.create(name_blob=b"U" * NAME_LEN)

    services.rename(target.id, b"V" * NAME_LEN)

    bystander.refresh_from_db()
    assert bytes(bystander.name_blob) == b"U" * NAME_LEN


def test_require_room_passes_silently_for_a_room_that_exists():
    room = Room.objects.create(name_blob=b"E" * NAME_LEN)

    assert services.require_room(room.id) is None


def test_require_room_raises_the_same_404_the_read_does():
    """The mint uses this instead of `read`, so the two must be indistinguishable
    to a client: one shape of 404 for an unknown room, whichever route asked."""
    with pytest.raises(ApiError) as caught:
        services.require_room(uuid.uuid4())

    assert (caught.value.status_code, caught.value.code) == (404, "not_found")
    assert caught.value.detail == services.NOT_FOUND


@pytest.mark.parametrize("bucket", NAME_BUCKETS)
def test_a_name_of_either_bucket_survives_create_and_read_unchanged(bucket):
    """The boundary of the round trip: the blob the client gets back has to be the
    blob it sent, for both declared lengths."""
    blob = base64.b64encode(b"W" * bucket).decode()

    created = services.create(b"W" * bucket)

    assert services.read(created["room_id"])["name_blob"] == blob


@settings(max_examples=25)
@given(payload=st.binary(min_size=NAME_LEN, max_size=NAME_LEN))
def test_any_bucket_sized_ciphertext_round_trips_through_the_column(payload):
    """The column is `bytea` holding opaque ciphertext, so no byte value in it is
    special — a NUL, a high byte and a UTF-8 fragment all read back unchanged."""
    created = services.create(payload)

    room = Room.objects.get(id=created["room_id"])
    assert bytes(room.name_blob) == payload
    assert base64.b64decode(services.read(room.id)["name_blob"]) == payload
