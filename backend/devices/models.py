import uuid

from django.db import models

from core.buckets import KEYPACKAGE_BUCKETS, LABEL_BUCKETS
from core.fields import OpaqueBlobField


class Device(models.Model):
    """A registered client device (ARCHITECTURE §A4).

    Every key column here holds a **public** key, opaque to the server. Endpoints,
    the claim race, and the revocation cascade are built in the devices phase.
    """

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
    # Bumping this invalidates every outstanding JWT for this device (§A8).
    token_generation = models.PositiveIntegerField(default=1)
    created_date = models.DateField(auto_now_add=True)
    last_active_date = models.DateField(null=True)
    revoked_date = models.DateField(null=True)


class OneTimePrekey(models.Model):
    """X3DH one-time prekey. Claimed = deleted, inside the claim transaction (§A4)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device = models.ForeignKey(Device, on_delete=models.CASCADE,
                               related_name="onetime_prekeys")
    key_id = models.PositiveIntegerField()
    pub = models.BinaryField()

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["device", "key_id"],
                                    name="uniq_onetimeprekey_device_key_id"),
        ]


class KeyPackage(models.Model):
    """Opaque MLS KeyPackage, claimed-once (delete-on-claim) (§A4)."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    device = models.ForeignKey(Device, on_delete=models.CASCADE,
                               related_name="key_packages")
    blob = OpaqueBlobField(bucket_set=KEYPACKAGE_BUCKETS)
    created_date = models.DateField(auto_now_add=True)
