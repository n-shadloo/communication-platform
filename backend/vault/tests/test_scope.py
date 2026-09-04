"""A register-scope token's only power is POST /me/devices.

The vault endpoint holds the recovery-protected key backup, so it may not admit a
register-scope token.
"""

import pytest

from .conftest import KEYBACKUP_URL, backup_blob

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)


def endpoints():
    return {
        "read key backup": ("GET", None),
        "write key backup": ("PUT", {"blob": backup_blob(), "version": 1}),
    }


@pytest.mark.parametrize("name", list(endpoints()))
def test_a_register_scope_token_reaches_no_vault_endpoint(
    http, active_user, register_bearer, name
):
    method, body = endpoints()[name]
    kwargs = {"headers": register_bearer(active_user)}
    if body is not None:
        kwargs["json"] = body
    resp = http.request(method, KEYBACKUP_URL, **kwargs)
    assert resp.status_code == 403, f"{name} admitted a register-scope token"
    assert resp.json()["code"] == "scope_forbidden"


def test_full_scope_is_accepted(http, active_user, device, bearer):
    """Guards the guard: the 403s above must be about scope, not a broken token."""
    resp = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(), "version": 1},
        headers=bearer(active_user, device),
    )
    assert resp.status_code == 200
