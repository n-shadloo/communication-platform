"""A register-scope token's only power is POST /me/devices.

The vault endpoint holds the recovery-protected key backup, so it may not admit a
register-scope token.
"""

import pytest

from accounts.tokens import issue_register_scope

from .conftest import KEYBACKUP_URL, backup_blob

pytestmark = pytest.mark.django_db


def bearer(access):
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


@pytest.fixture
def register_headers(active_user):
    return bearer(issue_register_scope(active_user))


def endpoints():
    return {
        "read key backup": ("get", KEYBACKUP_URL, None),
        "write key backup": ("put", KEYBACKUP_URL, {"blob": backup_blob(), "version": 1}),
    }


@pytest.mark.parametrize("name", list(endpoints()))
def test_a_register_scope_token_reaches_no_vault_endpoint(api, register_headers, name):
    method, url, body = endpoints()[name]
    resp = (
        getattr(api, method)(url, body, format="json", **register_headers)
        if body is not None
        else getattr(api, method)(url, **register_headers)
    )
    assert resp.status_code == 403, f"{name} admitted a register-scope token"
    assert resp.json()["code"] == "scope_forbidden"


def test_full_scope_is_accepted(api, active_user, device, auth_headers):
    """Guards the guard: the 403s above must be about scope, not a broken token."""
    resp = api.put(
        KEYBACKUP_URL,
        {"blob": backup_blob(), "version": 1},
        format="json",
        **auth_headers(active_user, device),
    )
    assert resp.status_code == 200
