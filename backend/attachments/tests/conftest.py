import pytest

from accounts.models import User
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"


@pytest.fixture(autouse=True)
def attachments_root(settings, tmp_path):
    """Uploads must land in a temp dir, never the repo's media_root."""
    settings.ATTACHMENTS_ROOT = tmp_path
    return tmp_path


@pytest.fixture
def bob(db):
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)


@pytest.fixture
def bob_device(bob):
    return Device.objects.create(user=bob, ik_pub=b"ik", spk_id=1, spk_pub=b"spk",
                                 spk_sig=b"sig", registration_id=11)
