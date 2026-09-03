import os
from datetime import timedelta
from io import StringIO

import pytest
from django.core.management import call_command
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import OutstandingToken

from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS
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
    """A pruned envelope may have been an MLS commit the device can never re-obtain,
    so the prune must leave a per-device high-water mark for the drain to surface."""
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
def test_expired_refresh_tokens_are_flushed_and_live_ones_stay(active_user):
    """Token-issue times approximate login times, so they must age out of the DB with
    the refresh TTL."""
    expired = OutstandingToken.objects.create(
        user=active_user,
        jti="expired-jti",
        token="t1",
        expires_at=timezone.now() - timedelta(days=1),
    )
    OutstandingToken.objects.create(
        user=active_user,
        jti="live-jti",
        token="t2",
        expires_at=timezone.now() + timedelta(days=1),
    )

    output = run_prune()

    assert list(OutstandingToken.objects.values_list("jti", flat=True)) == ["live-jti"]
    assert "refresh tokens flushed: 1" in output
    assert expired.jti not in output


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
def test_stale_keypackages_rotate_out_but_the_last_resort_survives(active_user, settings):
    """KEYPACKAGE_TTL_DAYS ages out the consumable pool; the last-resort package
    is exempt — deleting it would make an idle device unaddable to groups, the
    exact failure it exists to prevent."""
    from datetime import timedelta as td

    from devices.models import KeyPackage

    settings.KEYPACKAGE_TTL_DAYS = 30
    device = make_device(active_user, 74)
    stale = KeyPackage.objects.create(device=device, blob=b"S" * 4096)
    fresh = KeyPackage.objects.create(device=device, blob=b"F" * 4096)
    last = KeyPackage.objects.create(device=device, blob=b"L" * 4096, is_last_resort=True)
    old = timezone.now().date() - td(days=31)
    KeyPackage.objects.filter(id__in=[stale.id, last.id]).update(created_date=old)

    output = run_prune()

    remaining = set(KeyPackage.objects.values_list("id", flat=True))
    assert remaining == {fresh.id, last.id}
    assert "keypackages pruned: 1" in output
    assert str(stale.id) not in output


@pytest.mark.django_db
def test_pruning_a_device_out_of_existence_takes_its_queue(active_user, settings):
    """Cascade check: deleting a device must not strand its queue rows."""
    doomed = make_device(active_user, 77)
    queue_row(doomed, 1)

    doomed.delete()

    assert QueuedEnvelope.objects.count() == 0
