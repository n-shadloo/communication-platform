import pytest
from django.core.cache import cache
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full, issue_register_scope
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"


@pytest.fixture(autouse=True)
def clear_throttle_cache():
    """DRF throttle counters live in the shared Redis cache, so without this they leak
    between tests and across whole runs (the login scope is 20/hour)."""
    cache.clear()
    yield


@pytest.fixture
def api():
    return APIClient()


@pytest.fixture
def active_user(db):
    """An account the owner has already activated."""
    return User.objects.create_user(username="alice", password=PASSWORD, is_active=True)


@pytest.fixture
def device(active_user):
    """A live device for `active_user`, enough to mint full-scope tokens."""
    return Device.objects.create(
        user=active_user,
        ik_pub=b"ik-public",
        spk_id=1,
        spk_pub=b"spk-public",
        spk_sig=b"spk-signature",
        registration_id=1001,
    )


@pytest.fixture
def auth_headers():
    """Build request headers for a user. `scope="register"` mints the short-lived
    token whose only power is adding a device."""

    def build(user, device=None, scope="full"):
        if scope == "register":
            access = issue_register_scope(user)
        else:
            access, _refresh = issue_full(user, device)
        return {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    return build
