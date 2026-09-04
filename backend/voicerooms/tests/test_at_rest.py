"""What a seized `voicerooms_room` table yields: rooms exist, with encrypted names.

No membership, no participant history, no room text; there is no table to hold any of
it. `transaction=True` matters for the dump tests: pg_dump runs in a separate process
over a separate connection and sees only committed rows.
"""

import pytest
from asgiref.sync import async_to_sync
from django.db import connection

from accounts.tests.test_at_rest import PG_DUMP, pg_dump_table
from api.redis import close_client, get_client
from core.buckets import NAME_BUCKETS
from messaging.tests.test_at_rest import copy_block
from voicerooms.models import Room
from voicerooms.presence import _key, room_join, room_leave

from .conftest import NAME_LEN

TABLE = "voicerooms_room"

# id + encrypted name + coarse dates. A column added here fails this test on purpose.
EXPECTED_COLUMNS = {"id", "name_blob", "created_date", "updated_date"}


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_a_seized_room_table_is_only_id_and_encrypted_name():
    Room.objects.create(name_blob=b"r" * NAME_LEN)

    cols, rows = copy_block(pg_dump_table(TABLE), TABLE)

    assert set(cols) == EXPECTED_COLUMNS, "the room table grew a column it must not have"
    assert len(rows) == 1

    # The stored name is exactly one NAME bucket of ciphertext (pg_dump renders bytea
    # as \x<hex>, backslash-escaped again by the COPY text format).
    hexed = rows[0]["name_blob"].lstrip("\\")
    assert hexed.startswith("x"), f"unexpected bytea rendering: {hexed[:8]}"
    assert len(hexed[1:]) // 2 in set(NAME_BUCKETS)

    # Dates are day-coarse DATE columns: `YYYY-MM-DD`, no time component at all.
    for col in ("created_date", "updated_date"):
        assert len(rows[0][col]) == 10, f"{col} is finer than a day: {rows[0][col]}"


@pytest.mark.django_db
def test_there_is_no_membership_participant_or_room_text_table_anywhere():
    """Live participants exist only in non-persistent Redis; membership is client-side
    state. The schema must have nowhere to persist either."""
    with connection.cursor() as cursor:
        tables = set(connection.introspection.table_names(cursor))

    assert TABLE in tables, "the room table itself is missing"
    offenders = [
        t
        for t in tables
        if t != TABLE
        and ("room" in t or "member" in t or "participant" in t or "roster" in t)
    ]
    assert offenders == [], f"a room-adjacent table exists at rest: {offenders}"


@pytest.mark.django_db
def test_the_model_declares_only_the_four_columns():
    """The schema half of the same guard, failing fast without pg_dump."""
    names = {f.name for f in Room._meta.get_fields()}
    assert names == {"id", "name_blob", "created_date", "updated_date"}


def row_counts():
    """Every table in the schema and how many rows it holds."""
    with connection.cursor() as cursor:
        tables = sorted(connection.introspection.table_names(cursor))
        counts = {}
        for table in tables:
            cursor.execute(f'SELECT COUNT(*) FROM "{table}"')
            counts[table] = cursor.fetchone()[0]
    return counts


async def join_then_leave(room_id):
    """The whole life of a live room — two devices in, both out — on one loop and
    one client, so nothing is left bound to a loop that has ended."""
    client = get_client()
    await room_join(room_id, "device-a")
    await room_join(room_id, "device-b")
    while_two_are_in = await client.exists(_key(room_id))
    await room_leave(room_id, "device-a")
    while_one_is_in = await client.exists(_key(room_id))
    await room_leave(room_id, "device-b")
    after_the_last_left = await client.exists(_key(room_id))
    await close_client()
    return while_two_are_in, while_one_is_in, after_the_last_left


@pytest.mark.django_db(transaction=True)
def test_live_membership_exists_only_as_a_redis_set_that_dies_with_its_last_member():
    """Presence is a key that exists while somebody is in the room and is gone the
    moment the room empties. Redis deletes a set when its last member is removed,
    so an empty room leaves nothing behind — not even an empty key."""
    room = Room.objects.create(name_blob=b"j" * NAME_LEN)

    assert async_to_sync(join_then_leave)(room.id) == (1, 1, 0)


@pytest.mark.django_db(transaction=True)
def test_a_room_that_was_joined_and_left_holds_nothing_extra_at_rest():
    """A seizure after a call must yield exactly what a seizure before it would.
    Counted over every table in the schema, because a participant row appearing
    anywhere at all is the failure this states."""
    room = Room.objects.create(name_blob=b"p" * NAME_LEN)
    before = row_counts()
    stored = Room.objects.values().get(id=room.id)

    async_to_sync(join_then_leave)(room.id)

    assert row_counts() == before
    assert Room.objects.values().get(id=room.id) == stored
