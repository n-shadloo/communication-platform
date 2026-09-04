"""Query-shape guards for the accounts routes.

Counted end to end through the composed application, so each number includes the
one query the authentication dependency makes: the device row joined to its
owner. `transaction=True` makes the transaction statements real BEGIN/COMMIT
rather than savepoints, and they are excluded here so the number is the database
work itself.

Every count is at or below what the REST Framework view cost, except the login
that names a device: rotating the refresh generation is a write that did not
exist before ADR-0006, and it costs the UPDATE and the read of the row at its new
value.
"""

import base64

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from accounts.models import ProfileBlob, User
from api.auth import issue_full
from conftest import PASSWORD
from core.buckets import PROFILE_BUCKETS

pytestmark = pytest.mark.django_db(transaction=True)

TRANSACTION_STATEMENTS = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE", "ROLLBACK")

AUTH_QUERY = 1  # the device row, joined to its owner

REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
LOGOUT_URL = "/api/v1/auth/logout"
DIRECTORY_URL = "/api/v1/users"
MY_PROFILE_URL = "/api/v1/me/profile"


def queries(context):
    return [
        query["sql"]
        for query in context.captured_queries
        if not query["sql"].startswith(TRANSACTION_STATEMENTS)
    ]


def counted(http, method, url, expected, **kwargs):
    with CaptureQueriesContext(connection) as context:
        response = http.request(method, url, **kwargs)
    sqls = queries(context)
    assert len(sqls) == expected, "\n".join(sqls)
    return response


def blob_of(nbytes):
    return base64.b64encode(b"\x07" * nbytes).decode()


def test_registration_is_one_insert(http):
    response = counted(
        http,
        "POST",
        REGISTER_URL,
        1,
        json={"username": "zed", "password": "a-sufficiently-long-passphrase"},
    )

    assert response.status_code == 201


def test_login_without_a_device_reads_the_account_once(http, active_user):
    """The one query is the account row. A caller with no device gets a
    register-scope token, which needs no device row at all."""
    response = counted(
        http, "POST", LOGIN_URL, 1, json={"username": "alice", "password": PASSWORD}
    )

    assert response.json()["scope"] == "register"


def test_login_with_a_device_costs_the_generation_rotation(http, active_user, device):
    """The account row, the UPDATE that advances the refresh generation, and the
    read of the row at its new value. The UPDATE is what retires the refresh
    tokens the device already held."""
    response = counted(
        http,
        "POST",
        LOGIN_URL,
        3,
        json={
            "username": "alice",
            "password": PASSWORD,
            "device_id": str(device.id),
        },
    )

    assert response.json()["scope"] == "full"


def test_a_rotation_is_one_locked_read_and_one_update(http, active_user, device):
    """Refresh runs every access lifetime per device, so its shape is load-bearing.
    The device row is fetched with `.only(...)` over a select_related join, so
    touching a column outside that set would silently add a deferred load."""
    _access, refresh = issue_full(active_user, device)

    response = counted(http, "POST", REFRESH_URL, 2, json={"refresh": refresh})

    assert response.status_code == 200


def test_logout_is_the_authentication_and_one_update(http, active_user, device, bearer):
    response = counted(
        http, "POST", LOGOUT_URL, AUTH_QUERY + 1, headers=bearer(active_user, device)
    )

    assert response.status_code == 204


@pytest.mark.parametrize("account_count", [1, 26])
def test_the_directory_is_constant_query(
    http, active_user, device, bearer, account_count
):
    for index in range(account_count - 1):
        User.objects.create_user(
            username=f"user{index:02d}", password=PASSWORD, is_active=True
        )

    response = counted(
        http, "GET", DIRECTORY_URL, AUTH_QUERY + 1, headers=bearer(active_user, device)
    )

    assert len(response.json()["users"]) == account_count


def test_reading_a_profile_is_one_lookup(http, active_user, device, bearer):
    ProfileBlob.objects.create(
        user=active_user, blob=b"\x01" * PROFILE_BUCKETS[0], version=1
    )

    counted(
        http,
        "GET",
        f"/api/v1/users/{active_user.id}/profile",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )
    counted(
        http,
        "GET",
        MY_PROFILE_URL,
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )


def test_a_profile_write_reads_the_row_once(http, active_user, device, bearer):
    """The locked version check and the write must not each SELECT the row."""
    headers = bearer(active_user, device)
    http.put(
        MY_PROFILE_URL,
        json={"blob": blob_of(PROFILE_BUCKETS[0]), "version": 1},
        headers=headers,
    )

    # the locked read, then the UPDATE
    response = counted(
        http,
        "PUT",
        MY_PROFILE_URL,
        AUTH_QUERY + 2,
        json={"blob": blob_of(PROFILE_BUCKETS[0]), "version": 2},
        headers=headers,
    )

    assert response.status_code == 200
