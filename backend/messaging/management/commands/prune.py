from datetime import timedelta

from django.conf import settings
from django.contrib.admin.models import LogEntry
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Max
from django.utils import timezone

from attachments.models import Attachment
from attachments.services import purge
from devices.models import Device
from messaging.models import QueuedEnvelope


class Command(BaseCommand):
    """Idempotent: every pass deletes only what is already past its TTL, so re-running
    it after a crash is safe."""

    help = "Prune expired queued envelopes, attachments and audit rows."

    def handle(self, *args, **options):
        envelopes = self._prune_envelopes()
        attachments, files = self._prune_attachments()
        audit_rows = self._prune_audit()

        # Counts only: an id or a blob written here would land in the timer's journal.
        self.stdout.write(f"envelopes pruned: {envelopes}")
        self.stdout.write(f"attachments pruned: {attachments} (files removed: {files})")
        self.stdout.write(f"audit rows pruned: {audit_rows}")

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
        # Through the same service the panel's own deletion uses, so the row and
        # the file always go in the same order by the same code. No audit row: an
        # expiry is not an administrative act and no operator performed it.
        return purge(
            Attachment.objects.filter(created_date__lt=cutoff).only("id").iterator()
        )

    @staticmethod
    def _prune_audit():
        """Retention on the admin audit log (ADR-0011).

        The rows name an operator, a time and an object, and for a deleted
        attachment the object id is that attachment's spent capability. Ninety days
        is long enough to answer "what did I change last quarter" and short enough
        that a seizure takes one quarter rather than the life of the deployment.
        """
        cutoff = timezone.now() - timedelta(days=settings.ADMIN_AUDIT_RETENTION_DAYS)
        deleted, _ = LogEntry.objects.filter(action_time__lt=cutoff).delete()
        return deleted
