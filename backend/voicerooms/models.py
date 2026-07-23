import uuid

from django.db import models

from core.buckets import NAME_BUCKETS
from core.fields import OpaqueBlobField


class Room(models.Model):
    """A persistent room is only an id (capability) plus an encrypted name.
    Membership, invites, roles, and media crypto state are client-side room-MLS
    state carried over mailbox envelopes; live participants exist only in
    non-persistent Redis."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name_blob = OpaqueBlobField(bucket_set=NAME_BUCKETS)
    created_date = models.DateField(auto_now_add=True)
    updated_date = models.DateField(auto_now=True)
