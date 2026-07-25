import base64

import pytest

from accounts.models import User
from core.buckets import BACKUP_BUCKETS
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"

KEYBACKUP_URL = "/api/v1/me/keybackup"


def backup_blob(filler=b"B", size=None):
    """Base64 of an exactly bucket-sized recovery blob."""
    size = size if size is not None else min(BACKUP_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def make_device(user, registration_id=1):
    return Device.objects.create(
        user=user, ik_pub=b"ik", spk_id=1, spk_pub=b"spk", spk_sig=b"sig",
        registration_id=registration_id,
    )


@pytest.fixture
def bob(db):
    """A second activated account; its key backup must stay independent of alice's."""
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)


@pytest.fixture
def bob_device(bob):
    return make_device(bob, 99)
