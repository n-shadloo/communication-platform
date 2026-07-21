import os
from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand
from django.utils import timezone

from attachments.models import Attachment
from messaging.models import QueuedEnvelope


class Command(BaseCommand):
    """Delete expired queue rows and attachments — the maintenance timer's job (§A13).

    Idempotent: every pass deletes only what is already past its TTL, so re-running it
    (or running it after a crash) is safe.
    """

    help = "Prune expired queued envelopes and attachments."

    def handle(self, *args, **options):
        envelopes = self._prune_envelopes()
        attachments, files = self._prune_attachments()
        # Counts only. An id or a blob written here would land in the timer's journal,
        # which is exactly the graph leak §A11.4 forbids.
        self.stdout.write(f"envelopes pruned: {envelopes}")
        self.stdout.write(f"attachments pruned: {attachments} (files removed: {files})")

    @staticmethod
    def _prune_envelopes():
        cutoff = timezone.now() - timedelta(days=settings.ENVELOPE_TTL_DAYS)
        deleted, _ = QueuedEnvelope.objects.filter(queued_hour__lt=cutoff).delete()
        return deleted

    @staticmethod
    def _prune_attachments():
        cutoff = timezone.now().date() - timedelta(days=settings.ATTACH_TTL_DAYS)
        expired_ids = []
        removed_files = 0
        # Unlink before deleting the row: a crash in between leaves a row whose bytes are
        # already gone, which the next pass clears. Dropping the row first would strand
        # the file forever, since GC only ever walks rows.
        for att in Attachment.objects.filter(created_date__lt=cutoff).only("id").iterator():
            try:
                os.remove(att.disk_path())
                removed_files += 1
            except FileNotFoundError:
                pass  # already gone; the row still needs clearing
            except OSError:
                # One unreadable file must not stop the whole sweep — the rows are
                # deleted in a single pass below, so an escaping error would stall
                # retention entirely, and retention is a privacy control (§A13).
                continue
            expired_ids.append(att.id)
        deleted, _ = Attachment.objects.filter(id__in=expired_ids).delete()
        return deleted, removed_files
