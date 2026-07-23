import base64

import pytest

from accounts.models import User
from core.buckets import BACKUP_BUCKETS, ENVELOPE_BUCKETS
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"

KEYBACKUP_URL = "/api/v1/me/keybackup"
HISTORY_URL = "/api/v1/me/history"
HISTORY_DELETE_URL = "/api/v1/me/history/delete"
HISTORY_USAGE_URL = "/api/v1/me/history/usage"


def backup_blob(filler=b"B", size=None):
    """Base64 of an exactly bucket-sized recovery blob."""
    size = size if size is not None else min(BACKUP_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def history_blob(filler=b"h", size=None):
    """Base64 of an exactly bucket-sized history record."""
    size = size if size is not None else min(ENVELOPE_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def uniq_history_blob(i, size=None):
    """A distinct bucket-sized blob per index, so a paged read can be checked in order
    and byte-for-byte."""
    size = size if size is not None else min(ENVELOPE_BUCKETS)
    raw = (f"rec-{i}".encode() + b"\x00" * size)[:size]
    return base64.b64encode(raw).decode()


def make_device(user, registration_id=1):
    return Device.objects.create(
        user=user, ik_pub=b"ik", spk_id=1, spk_pub=b"spk", spk_sig=b"sig",
        registration_id=registration_id,
    )


@pytest.fixture
def bob(db):
    """A second activated account; its history log must stay independent of alice's."""
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)


@pytest.fixture
def bob_device(bob):
    return make_device(bob, 99)
