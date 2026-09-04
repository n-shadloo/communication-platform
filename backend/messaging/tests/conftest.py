import base64

import pytest

from accounts.models import User
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"
SMALLEST_BUCKET = 1024


def envelope_blob(filler=b"a", size=SMALLEST_BUCKET):
    """Base64 of an exactly bucket-sized payload."""
    return base64.b64encode((filler * size)[:size]).decode()


def make_device(user, registration_id=1):
    return Device.objects.create(
        user=user,
        ik_pub=b"ik",
        spk_id=1,
        spk_pub=b"spk",
        spk_sig=b"sig",
        registration_id=registration_id,
    )


@pytest.fixture(autouse=True)
def in_memory_channel_layer(settings):
    """Keep `_push` off Redis: repeated async_to_sync calls against a real channel layer
    leave closed event loops behind, and the in-memory layer lets a test actually observe
    what was pushed."""
    settings.CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
    }


@pytest.fixture
def bob(db):
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)


@pytest.fixture
def carol(db):
    return User.objects.create_user(username="carol", password=PASSWORD, is_active=True)


@pytest.fixture
def bob_devices(bob):
    return [make_device(bob, 11), make_device(bob, 12)]


@pytest.fixture
def carol_device(carol):
    return make_device(carol, 21)
