import base64
import binascii

from django.db import models


class OpaqueBlobField(models.BinaryField):
    """bytea that only ever holds opaque ciphertext of an exact bucket length; the
    server never parses contents."""

    def __init__(self, *args, bucket_set=None, **kwargs):
        self.bucket_set = set(bucket_set or [])
        kwargs.setdefault("editable", False)
        super().__init__(*args, **kwargs)

    def deconstruct(self):
        name, path, args, kwargs = super().deconstruct()
        kwargs["bucket_set"] = sorted(self.bucket_set)
        return name, path, args, kwargs


def decode_blob_or_400(b64_str, bucket_set):
    """Decode base64 and require an exact bucket length. Raises BadBucket (mapped to
    HTTP 400 {"code":"bad_bucket"}) without echoing the payload."""
    try:
        raw = base64.b64decode(b64_str, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise BadBucket()
    if len(raw) not in set(bucket_set):
        raise BadBucket()
    return raw


class BadBucket(Exception):
    pass
