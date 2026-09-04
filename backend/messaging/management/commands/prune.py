import os
from datetime import timedelta

from django.conf import settings
from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Max
from django.utils import timezone
from rest_framework_simplejwt.token_blacklist.models import OutstandingToken

from attachments.models import Attachment
from devices.models import Device
from messaging.models import QueuedEnvelope


class Command(BaseCommand):
    """Idempotent: every pass deletes only what is already past its TTL, so re-running
    it after a crash is safe."""

    help = "Prune expired queued envelopes and attachments."

    def handle(self, *args, **options):
        envelopes = self._prune_envelopes()
        tokens = self._flush_expired_refresh_tokens()
        attachments, files = self._prune_attachments()

        # Counts only: an id or a blob written here would land in the timer's journal.
        self.stdout.write(f"envelopes pruned: {envelopes}")
        self.stdout.write(f"refresh tokens flushed: {tokens}")
        self.stdout.write(f"attachments pruned: {attachments} (files removed: {files})")

    @staticmethod
    def _flush_expired_refresh_tokens():
        # Expired refresh JTIs are pruned so token-issue times age out of the DB.
        # SimpleJWT's own command does the delete; the count uses the same filter, and
        # blacklist rows cascade with their outstanding row.
        expired = OutstandingToken.objects.filter(expires_at__lte=timezone.now()).count()
        call_command("flushexpiredtokens")
        return expired

    @staticmethod
    def _prune_envelopes():
        cutoff = timezone.now() - timedelta(days=settings.ENVELOPE_TTL_DAYS)
        expired = QueuedEnvelope.objects.filter(queued_hour__lt=cutoff)
        with transaction.atomic():
            # Watermark before delete, in one transaction. A pruned envelope may have
            # carried a ratchet message or a group control event the device can never
            # re-obtain, so the device must be able to see that it missed something:
            # queue_pruned_through is that
            # signal (surfaced by GET /me/envelopes as `pruned_through`). Advancing
            # the watermark without the delete committing would tell a device it lost
            # envelopes it can still fetch, so both happen or neither does.
            # Aggregates only — seq per device, never ids or blobs into Python.
            per_device = expired.values("recipient_device_id").annotate(m=Max("seq"))
            for row in per_device:
                Device.objects.filter(
                    pk=row["recipient_device_id"],
                    queue_pruned_through__lt=row["m"],
                ).update(queue_pruned_through=row["m"])
            deleted, _ = expired.delete()
        return deleted

    @staticmethod
    def _prune_attachments():
        cutoff = timezone.now().date() - timedelta(days=settings.ATTACH_TTL_DAYS)
        expired_ids = []
        removed_files = 0
        # Unlink before deleting the row: a crash in between leaves a row whose bytes
        # are already gone, which the next pass clears. Dropping the row first would
        # strand the file, since cleanup only ever walks rows.
        for attachment in (
            Attachment.objects.filter(created_date__lt=cutoff).only("id").iterator()
        ):
            try:
                os.remove(attachment.disk_path())
                removed_files += 1
            except FileNotFoundError:
                pass  # already gone; the row still needs clearing
            except OSError:
                # One unreadable file must not stop the sweep. The rows are deleted in
                # a single pass below, so an escaping error would stall retention
                # entirely.
                continue
            expired_ids.append(attachment.id)
        deleted, _ = Attachment.objects.filter(id__in=expired_ids).delete()
        return deleted, removed_files
