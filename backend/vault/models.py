import uuid

from django.db import models

from core.buckets import BACKUP_BUCKETS, ENVELOPE_BUCKETS
from core.fields import OpaqueBlobField


class KeyBackup(models.Model):
    """The recovery-secret-encrypted backup. The server stores it and can never open
    it; no server-side secret verification exists anywhere."""

    user = models.OneToOneField("accounts.User", on_delete=models.CASCADE,
                                primary_key=True, related_name="keybackup")
    blob = OpaqueBlobField(bucket_set=BACKUP_BUCKETS)
    version = models.PositiveIntegerField(default=0)
    updated_date = models.DateField(auto_now=True)


class HistoryRecord(models.Model):
    """One record in the owner's own encrypted history log. `owner` is the log owner,
    not a conversation party; `blob` is ciphertext the server cannot read."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # db_index=False: the unique (owner, seq) constraint below already creates a btree
    # whose leading column serves every owner-only lookup, so a separate single-column
    # index would only amplify writes on the append path.
    owner = models.ForeignKey("accounts.User", on_delete=models.CASCADE,
                              related_name="history", db_index=False)
    seq = models.BigIntegerField()
    blob = OpaqueBlobField(bucket_set=ENVELOPE_BUCKETS)
    stored_date = models.DateField(auto_now_add=True)

    class Meta:
        # The unique (owner, seq) index also serves keyset paging and the Max(seq)
        # append probe, so a separate Index(owner, seq) is deliberately not declared.
        constraints = [models.UniqueConstraint(
            fields=["owner", "seq"], name="uq_history_owner_seq")]
