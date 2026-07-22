import uuid
from django.db import models
from core.fields import OpaqueBlobField
from core.buckets import BACKUP_BUCKETS, ENVELOPE_BUCKETS

class KeyBackup(models.Model):
    """The recovery-secret-encrypted key backup. The server stores it and can NEVER open it
    (§2.7). No server-side secret verification exists anywhere."""
    user = models.OneToOneField("accounts.User", on_delete=models.CASCADE,
                                primary_key=True, related_name="keybackup")
    blob = OpaqueBlobField(bucket_set=BACKUP_BUCKETS)
    version = models.PositiveIntegerField(default=0)
    updated_date = models.DateField(auto_now=True)

class HistoryRecord(models.Model):
    """One archive record in the owner's own encrypted history log. `owner` is the log owner,
    NOT a conversation party (§A4). `blob` is ciphertext under the owner's history key, which
    reaches the server only inside the (opaque) KeyBackup."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_index=False: the unique (owner, seq) constraint below already creates the
    # (owner, seq) btree, whose leading column serves every owner-only lookup (usage,
    # delete, cascade). A separate single-column owner_id index is pure write amplification
    # on the hot append path (measured: no query planned onto it).
    owner = models.ForeignKey("accounts.User", on_delete=models.CASCADE,
                              related_name="history", db_index=False)
    seq = models.BigIntegerField()
    blob = OpaqueBlobField(bucket_set=ENVELOPE_BUCKETS)
    stored_date = models.DateField(auto_now_add=True)

    class Meta:
        # The unique (owner, seq) index also serves keyset paging and the Max(seq) append
        # probe (ordered/backward scans on the same columns), so a duplicate
        # Index(owner, seq) would only add write cost — it is deliberately not declared.
        constraints = [models.UniqueConstraint(
            fields=["owner", "seq"], name="uq_history_owner_seq")]
