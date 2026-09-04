"""A register-scope token's only power is POST /me/devices.

The vault endpoint holds the recovery-protected key backup, so it may not admit a
register-scope token.
"""

import pytest

from vault.models import KeyBackup

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


@pytest.mark.parametrize("name", list(endpoints()))
def test_no_vault_endpoint_admits_an_anonymous_caller(http, name):
    """Guards the guard from below: the `403`s above are about the *scope* of a
    real token, so a missing token must be a different answer entirely."""
    method, body = endpoints()[name]
    kwargs = {"json": body} if body is not None else {}

    resp = http.request(method, KEYBACKUP_URL, **kwargs)

    assert resp.status_code == 401
    assert resp.json()["code"] == "unauthenticated"


@pytest.mark.parametrize("name", list(endpoints()))
def test_no_vault_endpoint_admits_a_token_shaped_string(http, name):
    method, body = endpoints()[name]
    kwargs = {"headers": {"Authorization": "Bearer eyJ.not.a.token"}}
    if body is not None:
        kwargs["json"] = body

    resp = http.request(method, KEYBACKUP_URL, **kwargs)

    assert resp.status_code == 401
    assert resp.json()["code"] == "invalid_token"


def test_the_scope_is_settled_before_the_body_is_looked_at(
    http, active_user, register_bearer
):
    """Ordering, and the reason it matters: a register-scope token that sent a
    malformed body must learn that it is the wrong scope, not the shape of the
    body it would need to send."""
    resp = http.put(
        KEYBACKUP_URL,
        json={"blob": 5, "version": "not a number", "junk": True},
        headers=register_bearer(active_user),
    )

    assert resp.status_code == 403
    assert resp.json()["code"] == "scope_forbidden"


def test_a_register_scope_write_stores_nothing(http, active_user, register_bearer):
    resp = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"N"), "version": 1},
        headers=register_bearer(active_user),
    )

    assert resp.status_code == 403
    assert KeyBackup.objects.count() == 0


def test_a_full_scope_token_reaches_only_its_own_accounts_backup(
    http, active_user, device, bearer, bob, bob_device
):
    """Both accounts hold a backup, so a `404` cannot be what separates them: the
    token itself selects the row, and there is no parameter with which to ask for
    anyone else's."""
    mine, theirs = backup_blob(b"A"), backup_blob(b"B")
    http.put(
        KEYBACKUP_URL,
        json={"blob": mine, "version": 1},
        headers=bearer(active_user, device),
    )
    http.put(
        KEYBACKUP_URL,
        json={"blob": theirs, "version": 1},
        headers=bearer(bob, bob_device),
    )

    read = http.get(KEYBACKUP_URL, headers=bearer(active_user, device))
    their_read = http.get(KEYBACKUP_URL, headers=bearer(bob, bob_device))
    assert read.json()["blob"] == mine
    assert their_read.json()["blob"] == theirs
