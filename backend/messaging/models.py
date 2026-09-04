import uuid

from django.db import models
from django.utils import timezone

from core.buckets import ENVELOPE_BUCKETS
from core.fields import OpaqueBlobField


def _truncate_hour(dt=None):
    dt = dt or timezone.now()
    return dt.replace(minute=0, second=0, microsecond=0)


class QueuedEnvelope(models.Model):
    """One padded ciphertext copy per recipient device. There is no sender column;
    sender identity exists only inside the ciphertext."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_index=False: the unique constraint below already indexes this column as its
    # leading key, so the default FK index would be a redundant B-tree maintained on
    # every insert.
    recipient_device = models.ForeignKey(
        "devices.Device", on_delete=models.CASCADE, related_name="queue", db_index=False
    )
    seq = models.BigIntegerField()
    blob = OpaqueBlobField(bucket_set=ENVELOPE_BUCKETS)
    queued_hour = models.DateTimeField(default=_truncate_hour, editable=False)

    class Meta:
        # The unique constraint doubles as the mailbox read index: the drain query is an
        # ordered scan of (recipient_device, seq), so a separate index would only add
        # per-insert maintenance.
        constraints = [
            models.UniqueConstraint(
                fields=["recipient_device", "seq"], name="uq_queue_device_seq"
            ),
        ]
