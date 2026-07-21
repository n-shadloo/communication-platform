import uuid

from django.db import models
from django.utils import timezone

from core.buckets import ENVELOPE_BUCKETS
from core.fields import OpaqueBlobField


def _truncate_hour(dt=None):
    dt = dt or timezone.now()
    return dt.replace(minute=0, second=0, microsecond=0)


class QueuedEnvelope(models.Model):
    """One opaque, padded, per-recipient-device copy. No sender column exists — sender
    identity lives only inside the ciphertext (structural sealed sender at rest, §A4)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_index=False: the unique constraint below already indexes this column as its
    # leading key, so Django's default FK index would be a third B-tree maintained on
    # every insert — and inserting is what this table does most.
    recipient_device = models.ForeignKey("devices.Device", on_delete=models.CASCADE,
                                         related_name="queue", db_index=False)
    seq = models.BigIntegerField()
    blob = OpaqueBlobField(bucket_set=ENVELOPE_BUCKETS)
    queued_hour = models.DateTimeField(default=_truncate_hour, editable=False)

    class Meta:
        # The unique constraint is also the mailbox's read index: §A4's "unique + idx
        # (recipient_device, seq)" is one physical B-tree, not two. Dropping the separate
        # models.Index leaves the drain plan identical (an ordered index scan with no
        # sort node) while cutting index maintenance per insert.
        constraints = [
            models.UniqueConstraint(fields=["recipient_device", "seq"],
                                    name="uq_queue_device_seq"),
        ]
