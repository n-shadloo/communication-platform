import uuid

from django.db import models

from core.buckets import NAME_BUCKETS
from core.fields import OpaqueBlobField


class Room(models.Model):
    """A persistent room is ONLY an id (capability) + an encrypted name. Membership, invites,
    roles, and audio keys are client room-MLS state carried over mailbox envelopes; live
    participants exist only in non-persistent Redis (§5.3, §A9)."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name_blob = OpaqueBlobField(bucket_set=NAME_BUCKETS)
    created_date = models.DateField(auto_now_add=True)
    updated_date = models.DateField(auto_now=True)
