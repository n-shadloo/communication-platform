import os
from contextlib import contextmanager
from datetime import timedelta
from io import StringIO
from unittest import mock

import psycopg
import pytest
from django.contrib.admin.models import ADDITION, LogEntry
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import DatabaseError, connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS
from devices.models import Device
from messaging.management.commands import prune
from messaging.models import QueuedEnvelope

from .conftest import SMALLEST_BUCKET, make_device


def run_prune():
    out = StringIO()
    call_command("prune", stdout=out)
    return out.getvalue()


def queue_row(device, seq, age_days=0):
    row = QueuedEnvelope.objects.create(
        recipient_device=device, seq=seq, blob=b"a" * SMALLEST_BUCKET
    )
    if age_days:
        QueuedEnvelope.objects.filter(id=row.id).update(
            queued_hour=timezone.now() - timedelta(days=age_days)
        )
    return row


def stored_attachment(user, root, age_days=0):
    attachment = Attachment.objects.create(uploader=user, size=min(ATTACHMENT_BUCKETS))
    path = root / attachment.id[:2] / attachment.id
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x01" * min(ATTACHMENT_BUCKETS))
    if age_days:
        Attachment.objects.filter(id=attachment.id).update(
            created_date=timezone.now().date() - timedelta(days=age_days)
        )
    return attachment, path


@pytest.fixture
def attachments_root(settings, tmp_path):
    settings.ATTACHMENTS_ROOT = tmp_path
    return tmp_path


@pytest.fixture
def expired_audit_rows(active_user, settings):
    """Five audit rows past the retention window, so a batch of two takes three
    passes."""
    rows = [
        LogEntry.objects.create(
            user=active_user, object_repr="x", action_flag=ADDITION, change_message=""
        )
        for _ in range(5)
    ]
    LogEntry.objects.filter(pk__in=[row.pk for row in rows]).update(
        action_time=timezone.now()
        - timedelta(days=settings.ADMIN_AUDIT_RETENTION_DAYS + 1)
    )
    return rows


@pytest.mark.django_db
def test_expired_queue_rows_go_and_fresh_ones_stay(device, settings):
    settings.ENVELOPE_TTL_DAYS = 30
    fresh = queue_row(device, 1)
    expired = queue_row(device, 2, age_days=31)

    output = run_prune()

    assert list(QueuedEnvelope.objects.values_list("id", flat=True)) == [fresh.id]
    assert "envelopes pruned: 1" in output
    assert str(expired.id) not in output


@pytest.mark.django_db
def test_expired_attachments_lose_both_row_and_bytes(
    active_user, attachments_root, settings
):
    settings.ATTACH_TTL_DAYS = 30
    fresh, fresh_path = stored_attachment(active_user, attachments_root)
    expired, expired_path = stored_attachment(active_user, attachments_root, age_days=31)

    output = run_prune()

    assert list(Attachment.objects.values_list("id", flat=True)) == [fresh.id]
    assert fresh_path.exists()
    assert not expired_path.exists()
    assert "attachments pruned: 1 (files removed: 1)" in output


@pytest.mark.django_db
def test_a_missing_file_does_not_stop_the_row_being_cleared(
    active_user, attachments_root, settings
):
    settings.ATTACH_TTL_DAYS = 30
    expired, path = stored_attachment(active_user, attachments_root, age_days=31)
    path.unlink()  # a previous run died between unlink and delete

    output = run_prune()

    assert not Attachment.objects.filter(id=expired.id).exists()
    assert "attachments pruned: 1 (files removed: 0)" in output


@pytest.mark.django_db
def test_one_unremovable_file_does_not_stall_the_whole_sweep(
    active_user, attachments_root, settings, monkeypatch
):
    """Rows are cleared in one pass after the loop, so an escaping OSError would stop
    retention altogether."""
    settings.ATTACH_TTL_DAYS = 30
    stuck, stuck_path = stored_attachment(active_user, attachments_root, age_days=31)
    ok, ok_path = stored_attachment(active_user, attachments_root, age_days=31)
    real_remove = os.remove

    def refuse_one(path, *args, **kwargs):
        if str(path) == str(stuck_path):
            raise PermissionError(13, "Permission denied")
        return real_remove(path, *args, **kwargs)

    monkeypatch.setattr(os, "remove", refuse_one)

    output = run_prune()

    # The healthy row is gone; the stuck one keeps its row so the next run retries it.
    assert not Attachment.objects.filter(id=ok.id).exists()
    assert Attachment.objects.filter(id=stuck.id).exists()
    assert not ok_path.exists()
    assert "attachments pruned: 1 (files removed: 1)" in output


@pytest.mark.django_db
def test_pruning_sets_the_watermark_to_the_max_pruned_seq_per_device(
    active_user, settings
):
    """A pruned envelope may have carried a ratchet message or a control event the
    device can never re-obtain, so the prune must leave a per-device high-water mark
    for the drain to surface."""
    settings.ENVELOPE_TTL_DAYS = 7
    lagging = make_device(active_user, 71)
    current = make_device(active_user, 72)
    queue_row(lagging, 3, age_days=8)
    queue_row(lagging, 4, age_days=8)
    queue_row(lagging, 5)  # fresh: survives, stays above the watermark
    queue_row(current, 9, age_days=8)

    run_prune()

    lagging.refresh_from_db()
    current.refresh_from_db()
    assert lagging.queue_pruned_through == 4
    assert current.queue_pruned_through == 9
    assert list(QueuedEnvelope.objects.values_list("seq", flat=True)) == [5]


@pytest.mark.django_db
def test_the_watermark_is_idempotent_and_never_regresses(active_user, settings):
    settings.ENVELOPE_TTL_DAYS = 7
    device = make_device(active_user, 73)
    queue_row(device, 6, age_days=8)

    run_prune()
    device.refresh_from_db()
    first = device.queue_pruned_through

    # A second pass deletes nothing and must not move the mark; nor may a later
    # pass over lower-seq stragglers pull it backwards.
    run_prune()
    queue_row(device, 2, age_days=8)
    run_prune()

    device.refresh_from_db()
    assert first == 6
    assert device.queue_pruned_through == 6


@pytest.mark.django_db
def test_prune_is_safe_to_run_repeatedly(device, active_user, attachments_root, settings):
    settings.ENVELOPE_TTL_DAYS = 30
    settings.ATTACH_TTL_DAYS = 30
    queue_row(device, 1, age_days=31)
    stored_attachment(active_user, attachments_root, age_days=31)

    first = run_prune()
    second = run_prune()

    assert "envelopes pruned: 1" in first
    assert "envelopes pruned: 0" in second
    assert "attachments pruned: 0 (files removed: 0)" in second


@pytest.mark.django_db
def test_prune_prints_counts_but_never_an_identifier(
    device, active_user, attachments_root, settings
):
    """The timer's stdout lands in the journal, so an id here would be a graph leak."""
    settings.ENVELOPE_TTL_DAYS = 30
    settings.ATTACH_TTL_DAYS = 30
    row = queue_row(device, 1, age_days=31)
    attachment, _path = stored_attachment(active_user, attachments_root, age_days=31)

    output = run_prune()

    for identifier in (str(row.id), str(device.id), str(active_user.id), attachment.id):
        assert identifier not in output


@pytest.mark.django_db
def test_pruning_a_device_out_of_existence_takes_its_queue(active_user, settings):
    """Cascade check: deleting a device must not strand its queue rows."""
    doomed = make_device(active_user, 77)
    queue_row(doomed, 1)

    doomed.delete()

    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db
def test_the_retention_filter_column_carries_an_index():
    """The sweep runs hourly and filters the largest table on `queued_hour` alone.

    Without an index that filter is a sequential scan of the whole table on every
    pass, including the common pass where nothing has expired at all. Measured on
    a seeded copy (200 000 envelopes, 245 MB): 28 736 buffers and 26.5 ms with
    nothing to delete, against 2 buffers and 0.012 ms once the index exists. The
    plans are recorded in `docs/architecture/GROUND-TRUTH.md`.
    """
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT indexdef FROM pg_indexes WHERE tablename = %s",
            [QueuedEnvelope._meta.db_table],
        )
        definitions = [row[0] for row in cursor.fetchall()]

    assert any("(queued_hour" in definition for definition in definitions), definitions


# --- The sweep as background work -------------------------------------------------


@contextmanager
def another_session():
    """A second PostgreSQL session, outside Django's connection.

    An advisory lock belongs to the backend that took it, so proving the guard
    needs a second backend. Built from the parameters Django would use, minus the
    two objects that are Django's own machinery rather than connection settings.
    """
    params = {
        key: value
        for key, value in connection.get_connection_params().items()
        if key not in ("cursor_factory", "context")
    }
    session = psycopg.connect(**params, autocommit=True)
    try:
        yield session
    finally:
        session.close()


def deletes_of(context, table):
    return [
        query["sql"]
        for query in context.captured_queries
        if query["sql"].startswith("DELETE") and table in query["sql"]
    ]


@pytest.mark.django_db(transaction=True)
def test_the_envelope_sweep_deletes_in_batches_that_bound_its_lock_time(
    active_user, settings, monkeypatch
):
    """One unbounded DELETE holds a row lock on every expired envelope until it
    commits, and the sweep runs beside live traffic rather than in a window. The
    mailbox ceiling times the device count is what that delete could be."""
    settings.ENVELOPE_TTL_DAYS = 7
    monkeypatch.setattr(prune, "BATCH", 2)
    device = make_device(active_user, 81)
    for seq in range(1, 6):
        queue_row(device, seq, age_days=8)

    with CaptureQueriesContext(connection) as context:
        run_prune()

    assert deletes_of(context, "messaging_queuedenvelope") != []
    assert len(deletes_of(context, "messaging_queuedenvelope")) == 3  # 2 + 2 + 1
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db(transaction=True)
def test_the_audit_sweep_deletes_in_batches_too(
    expired_audit_rows, settings, monkeypatch
):
    settings.ADMIN_AUDIT_RETENTION_DAYS = 90
    monkeypatch.setattr(prune, "BATCH", 2)

    with CaptureQueriesContext(connection) as context:
        run_prune()

    assert len(deletes_of(context, "django_admin_log")) == 3  # 2 + 2 + 1
    assert LogEntry.objects.count() == 0


@pytest.mark.django_db(transaction=True)
def test_the_watermark_of_a_batch_is_one_update_however_many_devices(
    active_user, settings
):
    """The mark used to be raised one device at a time, which is a query per device
    with expired mail inside the transaction that holds the delete."""
    settings.ENVELOPE_TTL_DAYS = 7
    for index in range(4):
        queue_row(make_device(active_user, 90 + index), index + 1, age_days=8)

    with CaptureQueriesContext(connection) as context:
        run_prune()

    updates = [
        query["sql"]
        for query in context.captured_queries
        if query["sql"].startswith("UPDATE") and "devices_device" in query["sql"]
    ]
    assert len(updates) == 1
    assert list(
        Device.objects.order_by("registration_id").values_list(
            "queue_pruned_through", flat=True
        )
    ) == [1, 2, 3, 4]


@pytest.mark.django_db(transaction=True)
def test_a_sweep_declines_while_another_session_holds_the_lock(active_user, settings):
    """Two sweeps interleaved would advance one device's watermark from one batch
    while the other deletes a different one, and the device would be told it lost
    envelopes that are still in its mailbox. systemd declining to start a second
    `Type=oneshot` instance is the state of the unit at one instant, not a lock,
    and an operator running this by hand is outside the unit entirely."""
    settings.ENVELOPE_TTL_DAYS = 7
    device = make_device(active_user, 95)
    queue_row(device, 1, age_days=8)

    with another_session() as session:
        session.execute(
            "SELECT pg_advisory_lock(%s, %s)",
            [prune.LOCK_NAMESPACE, prune.LOCK_RESOURCE],
        )
        output = run_prune()

    assert prune.SKIPPED in output
    assert QueuedEnvelope.objects.count() == 1
    device.refresh_from_db()
    assert device.queue_pruned_through == 0


@pytest.mark.django_db(transaction=True)
def test_the_lock_is_released_so_the_next_run_sweeps(active_user, settings):
    """A session lock outlives every transaction of the sweep, so nothing but the
    command's own release ends it while the process lives."""
    settings.ENVELOPE_TTL_DAYS = 7
    queue_row(make_device(active_user, 96), 1, age_days=8)

    run_prune()
    queue_row(make_device(active_user, 97), 1, age_days=8)
    second = run_prune()

    assert prune.SKIPPED not in second
    assert QueuedEnvelope.objects.count() == 0


@pytest.mark.django_db(transaction=True)
def test_a_failed_sweep_names_the_step_and_nothing_else(active_user, settings):
    """The statements of this command carry envelope ids, and a database error
    carries the statement that raised it — so an escaping traceback writes a
    device's mailbox into the timer's journal. `CommandError` is also what makes
    the exit status 1 instead of a traceback."""
    settings.ENVELOPE_TTL_DAYS = 7
    device = make_device(active_user, 98)
    row = queue_row(device, 1, age_days=8)
    leaky = DatabaseError(f"DELETE FROM messaging_queuedenvelope WHERE id = '{row.id}'")

    with mock.patch.object(Device.objects, "filter", side_effect=leaky):
        with pytest.raises(CommandError) as raised:
            run_prune()

    assert "envelope sweep" in str(raised.value)
    assert str(row.id) not in str(raised.value)
    assert str(device.id) not in str(raised.value)


@pytest.mark.django_db(transaction=True)
def test_a_failed_sweep_exits_non_zero(active_user, settings, capsys):
    """The real exit path, not the `call_command` one: `run_from_argv` turns a
    `CommandError` into `sys.exit(1)`, which is what the timer's unit reads."""
    settings.ENVELOPE_TTL_DAYS = 7
    queue_row(make_device(active_user, 99), 1, age_days=8)

    with mock.patch.object(Device.objects, "filter", side_effect=DatabaseError("x")):
        with pytest.raises(SystemExit) as exit_status:
            prune.Command().run_from_argv(["manage.py", "prune"])

    assert exit_status.value.code == 1
    assert "envelope sweep" in capsys.readouterr().err


@pytest.mark.django_db(transaction=True)
def test_a_skipped_sweep_exits_zero(active_user, settings, capsys):
    """A run that declines the lock has done the right thing. Exiting non-zero
    would leave the timer's unit in a failed state for it."""
    settings.ENVELOPE_TTL_DAYS = 7
    queue_row(make_device(active_user, 100), 1, age_days=8)

    with another_session() as session:
        session.execute(
            "SELECT pg_advisory_lock(%s, %s)",
            [prune.LOCK_NAMESPACE, prune.LOCK_RESOURCE],
        )
        prune.Command().run_from_argv(["manage.py", "prune"])

    assert prune.SKIPPED in capsys.readouterr().out
    assert QueuedEnvelope.objects.count() == 1
