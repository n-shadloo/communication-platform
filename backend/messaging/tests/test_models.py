"""What the queue table guarantees on its own, below every route.

Three kinds of promise live here rather than in the service layer, and a change
to `messaging/models.py` is the only thing that can break them:

* the state a row is *born* in — its own identifier, and a timestamp coarsened to
  the hour before it ever reaches the column;
* the width of `seq`, which is what lets a mailbox counter run past a 32-bit
  ceiling instead of failing the send that crosses it;
* the index set, since the drain, the ack and the hourly retention sweep each
  rest on one of them and a redundant fourth would be maintained on every insert.

The bucket rule is deliberately absent: `OpaqueBlobField` declares the set the
schema layer enforces, and the field itself checks nothing, so the declaration is
what this file pins. `messaging/tests/test_schemas.py` holds the enforcement.
"""

from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

import pytest
from django.db import connection
from django.utils import timezone

from core.buckets import ENVELOPE_BUCKETS
from messaging.models import QueuedEnvelope, _truncate_hour

from .conftest import SMALLEST_BUCKET, make_device

pytestmark = pytest.mark.django_db


def indexes_on(model):
    """Every index the database actually holds for a table, as column tuples."""
    with connection.cursor() as cursor:
        constraints = connection.introspection.get_constraints(
            cursor, model._meta.db_table
        )
    return [
        tuple(entry["columns"])
        for entry in constraints.values()
        if entry.get("index") or entry.get("unique")
    ]


def test_the_hour_truncation_keeps_the_hour_and_drops_everything_below_it():
    stamp = datetime(2026, 3, 9, 17, 43, 21, 987654, tzinfo=dt_timezone.utc)

    assert _truncate_hour(stamp) == datetime(2026, 3, 9, 17, tzinfo=dt_timezone.utc)


def test_the_truncation_falls_back_to_the_clock_when_it_is_given_nothing():
    """The field's default is called with no argument, so this is the only path
    that ever runs in production."""
    before = timezone.now()

    truncated = _truncate_hour()

    assert (truncated.minute, truncated.second, truncated.microsecond) == (0, 0, 0)
    assert truncated <= before
    assert before - truncated < timedelta(hours=1)


def test_a_row_is_born_with_its_own_identifier_and_an_hour_coarse_timestamp(
    active_user,
):
    """Nothing finer than the hour reaches the column: a per-second timestamp
    would let a dump order two mailboxes against each other."""
    device = make_device(active_user, registration_id=31)

    row = QueuedEnvelope.objects.create(
        recipient_device=device, seq=1, blob=b"a" * SMALLEST_BUCKET
    )
    row.refresh_from_db()

    assert row.id is not None
    assert (row.queued_hour.minute, row.queued_hour.second) == (0, 0)
    assert row.queued_hour.microsecond == 0


def test_a_bulk_created_row_gets_the_same_coarse_timestamp_as_a_saved_one(active_user):
    """The send path inserts through `bulk_create`, which never calls `save()`:
    a default applied only in `save()` would leave the hot path writing NULL."""
    device = make_device(active_user, registration_id=32)

    QueuedEnvelope.objects.bulk_create(
        [QueuedEnvelope(recipient_device=device, seq=1, blob=b"a" * SMALLEST_BUCKET)]
    )

    stored = QueuedEnvelope.objects.get(recipient_device=device)
    assert (stored.queued_hour.minute, stored.queued_hour.second) == (0, 0)
    assert stored.queued_hour.microsecond == 0


def test_two_rows_of_the_same_device_never_share_an_identifier(active_user):
    device = make_device(active_user, registration_id=33)

    first = QueuedEnvelope.objects.create(
        recipient_device=device, seq=1, blob=b"a" * SMALLEST_BUCKET
    )
    second = QueuedEnvelope.objects.create(
        recipient_device=device, seq=2, blob=b"b" * SMALLEST_BUCKET
    )

    assert first.id != second.id


def test_one_seq_belongs_to_each_device_separately(active_user):
    """The complement of the unique constraint: `seq` is unique per mailbox, not
    globally, so every fresh device starts at 1 and two devices hold seq 1 at
    once. A global sequence would make row adjacency correlate two mailboxes."""
    first = make_device(active_user, registration_id=34)
    second = make_device(active_user, registration_id=35)

    QueuedEnvelope.objects.create(
        recipient_device=first, seq=1, blob=b"a" * SMALLEST_BUCKET
    )
    QueuedEnvelope.objects.create(
        recipient_device=second, seq=1, blob=b"b" * SMALLEST_BUCKET
    )

    assert QueuedEnvelope.objects.filter(seq=1).count() == 2


def test_a_seq_beyond_the_32_bit_ceiling_stores_and_reads_back(active_user):
    """`queue_seq` is a 64-bit counter that only ever climbs, so the column it is
    copied into has to be one too: in a 32-bit column the send that crossed the
    ceiling would be a `DataError` the client can never get past."""
    device = make_device(active_user, registration_id=36)
    past_the_ceiling = 2**31

    row = QueuedEnvelope.objects.create(
        recipient_device=device, seq=past_the_ceiling, blob=b"a" * SMALLEST_BUCKET
    )
    row.refresh_from_db()

    assert row.seq == past_the_ceiling


def test_the_rows_of_a_device_are_reachable_from_the_device_itself(active_user):
    """`related_name="queue"` is what the cascade and the admin both read."""
    device = make_device(active_user, registration_id=37)
    row = QueuedEnvelope.objects.create(
        recipient_device=device, seq=1, blob=b"a" * SMALLEST_BUCKET
    )

    assert list(device.queue.values_list("id", flat=True)) == [row.id]


def test_the_blob_column_declares_the_envelope_bucket_set_and_nothing_editable():
    """The declaration is the contract the schema layer enforces and the panel
    obeys; `editable=False` is what keeps a form from ever offering the column."""
    blob = QueuedEnvelope._meta.get_field("blob")

    assert blob.bucket_set == set(ENVELOPE_BUCKETS)
    assert blob.editable is False
    assert QueuedEnvelope._meta.get_field("queued_hour").editable is False
    assert QueuedEnvelope._meta.pk.editable is False


def test_the_bucket_set_travels_into_the_migration_rather_than_the_code_alone():
    """`deconstruct` is what a migration records, so a bucket change is a schema
    change an operator can see rather than a silent edit to a constant."""
    _name, _path, _args, kwargs = QueuedEnvelope._meta.get_field("blob").deconstruct()

    assert kwargs["bucket_set"] == sorted(ENVELOPE_BUCKETS)


def test_the_table_carries_the_mailbox_index_the_retention_index_and_no_third():
    """The unique constraint doubles as the ordered mailbox read, and the hourly
    sweep filters on `queued_hour` alone. A standalone index on the foreign key —
    which is what Django adds unless told not to — would be a redundant B-tree
    maintained on every insert into the largest table of the schema."""
    held = indexes_on(QueuedEnvelope)

    assert ("recipient_device_id", "seq") in held
    assert ("queued_hour",) in held
    assert ("recipient_device_id",) not in held
