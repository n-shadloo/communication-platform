import uuid

from django.db import models

from core.buckets import KEYPACKAGE_BUCKETS, LABEL_BUCKETS
from core.fields import OpaqueBlobField


class Device(models.Model):
    """A registered client device. Every key column holds a public key, opaque to
    the server."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey("accounts.User", on_delete=models.CASCADE,
                             related_name="devices")
    ik_pub = models.BinaryField()
    spk_id = models.PositiveIntegerField()
    spk_pub = models.BinaryField()
    spk_sig = models.BinaryField()
    spk_updated_date = models.DateField(auto_now_add=True)
    registration_id = models.PositiveIntegerField()
    label_blob = OpaqueBlobField(bucket_set=LABEL_BUCKETS, null=True)
    # Bumping this invalidates every outstanding JWT for this device.
    token_generation = models.PositiveIntegerField(default=1)
    created_date = models.DateField(auto_now_add=True)
    last_active_date = models.DateField(null=True)
    revoked_date = models.DateField(null=True)
    # Per-device envelope counter. Ordering the mailbox needs a monotonic number, and
    # a server-wide sequence would let row adjacency correlate activity across devices
    # in a dump. Incremented with an F() expression inside the enqueue transaction,
    # whose row lock is what makes concurrent assignment atomic.
    queue_seq = models.BigIntegerField(default=0)


class OneTimePrekey(models.Model):
    """X3DH one-time prekey. Claiming one deletes it, inside the claim transaction."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_index=False: the unique constraint below already indexes this column as its
    # leading key, so the default FK index would be a redundant B-tree maintained on
    # every insert.
    device = models.ForeignKey(Device, on_delete=models.CASCADE,
                               related_name="onetime_prekeys", db_index=False)
    key_id = models.PositiveIntegerField()
    pub = models.BinaryField()

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["device", "key_id"],
                                    name="uniq_onetimeprekey_device_key_id"),
        ]


class KeyPackage(models.Model):
    """Opaque MLS KeyPackage, deleted when claimed."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device = models.ForeignKey(Device, on_delete=models.CASCADE,
                               related_name="key_packages")
    blob = OpaqueBlobField(bucket_set=KEYPACKAGE_BUCKETS)
    created_date = models.DateField(auto_now_add=True)
