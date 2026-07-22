import base64

import pytest

from core.buckets import NAME_BUCKETS
from voicerooms.models import Room

NAME_LEN = min(NAME_BUCKETS)


def name_blob_b64(fill=b"n", length=NAME_LEN):
    """A base64 name blob of exactly one NAME bucket (the client pads, §A7)."""
    return base64.b64encode(fill * length).decode()


@pytest.fixture
def room(db):
    return Room.objects.create(name_blob=b"n" * NAME_LEN)
