"""What a seized `voicerooms_room` table yields: rooms exist, with encrypted names.

No membership, no participant history, no room text; there is no table to hold any of
it. `transaction=True` matters for the dump tests: pg_dump runs in a separate process
over a separate connection and sees only committed rows.
"""

import pytest
from django.db import connection

from accounts.tests.test_at_rest import PG_DUMP, pg_dump_table
from core.buckets import NAME_BUCKETS
from messaging.tests.test_at_rest import copy_block
from voicerooms.models import Room

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
