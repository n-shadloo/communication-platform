"""The one table this app owns.

`Room` is a design statement compressed into four columns: the primary key is a
random UUID because the id *is* the capability an encrypted invite carries, the
name is an opaque blob declared with the bucket set the route enforces, and the
two timestamps are dates so a seized row cannot say when in the day anybody was
awake. What is absent is the point — no owner, no member, no roster, no media
key, and no relation to any other table at all.

`voicerooms/tests/test_at_rest.py` asks the same question of a `pg_dump`; this
file asks it of the model and of the live schema, so it fails without pg_dump on
PATH too.
"""

import uuid

import pytest
from django.db import connection, models

from core.buckets import NAME_BUCKETS
from core.fields import OpaqueBlobField
from voicerooms.models import Room

from .conftest import NAME_LEN

pytestmark = pytest.mark.django_db(transaction=True)

COLUMNS = {"id", "name_blob", "created_date", "updated_date"}


def field(name):
    return Room._meta.get_field(name)


def test_creating_a_room_stores_the_bytes_it_was_given_under_a_random_uuid():
    room = Room.objects.create(name_blob=b"r" * NAME_LEN)

    room.refresh_from_db()
    assert isinstance(room.id, uuid.UUID)
    assert bytes(room.name_blob) == b"r" * NAME_LEN


def test_the_id_is_a_random_primary_key_the_client_never_chooses():
    """A sequential or client-supplied id would make one capability guessable from
    another; `uuid4` is what makes the id unguessable, and `editable=False` is what
    keeps a form or an admin page from setting it."""
    id_field = field("id")

    assert isinstance(id_field, models.UUIDField)
    assert id_field.primary_key
    assert id_field.default is uuid.uuid4
    assert not id_field.editable


def test_two_rooms_created_back_to_back_get_different_capabilities():
    """The rare case worth stating out loud: the id is the whole access control,
    so a collision or a reused id would hand one room's capability to another."""
    ids = {Room.objects.create(name_blob=b"n" * NAME_LEN).id for _ in range(8)}

    assert len(ids) == 8


def test_the_name_column_is_an_opaque_blob_declared_with_the_name_bucket_set():
    """The column and the request model must agree on the bucket set, or a blob
    the route accepts is one the column was never sized for."""
    name = field("name_blob")

    assert isinstance(name, OpaqueBlobField)
    assert name.bucket_set == set(NAME_BUCKETS)
    assert not name.editable


@pytest.mark.parametrize("bucket", NAME_BUCKETS)
def test_every_name_bucket_round_trips_byte_exact(bucket):
    """The boundary of the column: both declared bucket lengths store and read
    back unchanged, so no bucket is one the server silently truncates."""
    room = Room.objects.create(name_blob=b"b" * bucket)

    room.refresh_from_db()
    assert bytes(room.name_blob) == b"b" * bucket


def test_both_timestamps_are_day_coarse_and_maintained_by_the_orm():
    created, updated = field("created_date"), field("updated_date")

    assert type(created) is models.DateField and type(updated) is models.DateField
    assert (created.auto_now_add, created.auto_now) == (True, False)
    assert (updated.auto_now_add, updated.auto_now) == (False, True)


def test_a_model_save_bumps_the_updated_date_and_leaves_the_created_date_alone():
    """`auto_now` is what makes a rename visible to a peer polling `GET`. Predated
    first, because a row written today would show the same date either way."""
    room = Room.objects.create(name_blob=b"n" * NAME_LEN)
    Room.objects.filter(id=room.id).update(
        created_date="2020-01-01", updated_date="2020-01-01"
    )
    room.refresh_from_db()

    room.name_blob = b"m" * NAME_LEN
    room.save()

    room.refresh_from_db()
    assert str(room.created_date) == "2020-01-01"
    assert str(room.updated_date) != "2020-01-01"


def test_the_model_declares_the_four_columns_and_no_relation_to_anything():
    """A relation here would be an owner, a member or a roster — the state this
    server has never held and cannot be compelled to produce."""
    fields = Room._meta.get_fields()

    assert {f.name for f in fields} == COLUMNS
    assert [f.name for f in fields if f.is_relation] == []


def test_the_live_schema_holds_exactly_those_four_columns_and_no_foreign_key():
    """The database's own answer, not the model's. A column added by a migration
    that the model does not declare would pass the test above and fail here."""
    with connection.cursor() as cursor:
        described = connection.introspection.get_table_description(
            cursor, Room._meta.db_table
        )
        constraints = connection.introspection.get_constraints(
            cursor, Room._meta.db_table
        )

    assert {column.name for column in described} == COLUMNS
    assert [name for name, c in constraints.items() if c["foreign_key"]] == []


def test_the_only_unique_key_in_the_table_is_the_capability_itself():
    """A unique index on the name blob would turn the ciphertext into an oracle:
    an insert that failed would prove another room already holds those bytes."""
    with connection.cursor() as cursor:
        constraints = connection.introspection.get_constraints(
            cursor, Room._meta.db_table
        )

    unique = {
        tuple(c["columns"])
        for c in constraints.values()
        if c["unique"] or c["primary_key"]
    }
    assert unique == {("id",)}
