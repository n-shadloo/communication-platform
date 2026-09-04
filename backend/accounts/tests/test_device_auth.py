"""What the one token verifier accepts, and what it refuses.

`api.auth` is the only issuer and the only verifier in the system, so these cover
both stacks: the FastAPI routes below, and the REST Framework routes that reach
the same functions through `accounts.auth.DeviceJWTAuthentication`.
"""

import base64
import json
import uuid
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from django.conf import settings

from api.auth import issue_full, issue_register_scope
from core.buckets import NAME_BUCKETS

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)

DIRECTORY_URL = "/api/v1/users"
DEVICES_URL = "/api/v1/me/devices"
ROOMS_URL = "/api/v1/rooms"  # still REST Framework, until run 05
PROFILE_URL = "/api/v1/me/profile"
KEYBACKUP_URL = "/api/v1/me/keybackup"


def signed(claims):
    return jwt.encode(claims, settings.JWT_SIGNING_KEY, algorithm="HS256")


def live_claims(user, device, **overrides):
    issued = datetime.now(timezone.utc)
    claims = {
        "user_id": str(user.id),
        "device_id": str(device.id),
        "tgen": device.token_generation,
        "scope": "full",
        "typ": "access",
        "jti": uuid.uuid4().hex,
        "iat": issued,
        "exp": issued + timedelta(minutes=15),
    }
    claims.update(overrides)
    return claims


def unsigned(claims):
    """An `alg: none` token: a header, a payload, and an empty signature."""

    def segment(obj):
        raw = json.dumps(obj, default=str).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

    return f"{segment({'alg': 'none', 'typ': 'JWT'})}.{segment(claims)}."


def token(access):
    return {"Authorization": f"Bearer {access}"}


def test_a_live_device_token_is_accepted(http, active_user, device):
    access, _refresh = issue_full(active_user, device)

    assert http.get(DIRECTORY_URL, headers=token(access)).status_code == 200


def test_revoking_a_device_rejects_its_outstanding_access_token(
    http, active_user, device
):
    access, _refresh = issue_full(active_user, device)
    device.revoked_date = "2026-01-01"
    device.save(update_fields=["revoked_date"])

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_bumping_token_generation_rejects_outstanding_access_tokens(
    http, active_user, device
):
    access, _refresh = issue_full(active_user, device)
    device.token_generation += 1
    device.save(update_fields=["token_generation"])

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_deleting_the_device_rejects_its_token(http, active_user, device):
    access, _refresh = issue_full(active_user, device)
    device.delete()

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_deactivating_the_account_rejects_its_tokens(http, active_user, device):
    access, _refresh = issue_full(active_user, device)
    active_user.is_active = False
    active_user.save(update_fields=["is_active"])

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


@pytest.mark.parametrize(
    "method, url",
    [
        ("GET", DIRECTORY_URL),
        ("GET", "/api/v1/users/11111111-1111-1111-1111-111111111111/profile"),
        ("GET", PROFILE_URL),
        ("PUT", PROFILE_URL),
        ("GET", KEYBACKUP_URL),
        ("PUT", KEYBACKUP_URL),
        ("POST", "/api/v1/auth/logout"),
    ],
)
def test_register_scope_reaches_no_moved_route(http, active_user, method, url):
    """A register-scope token is authentic; the scope check is what holds the
    line, and it holds before any database read happens."""
    response = http.request(method, url, headers=token(issue_register_scope(active_user)))

    assert response.status_code == 403
    assert response.json()["code"] == "scope_forbidden"


def test_anonymous_requests_are_refused_with_a_challenge(http):
    response = http.get(DIRECTORY_URL)

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"
    assert response.headers["www-authenticate"] == "Bearer"


@pytest.mark.parametrize("header", ["", "Bearer", "Bearer ", "Token abc", "abc"])
def test_a_malformed_authorization_header_is_unauthenticated(http, header):
    response = http.get(DIRECTORY_URL, headers={"Authorization": header})

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"


def test_a_garbage_token_is_an_invalid_token(http):
    response = http.get(DIRECTORY_URL, headers=token("not-a-jwt"))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_an_expired_token_is_refused(http, active_user, device):
    expired = datetime.now(timezone.utc) - timedelta(minutes=1)
    access = signed(live_claims(active_user, device, exp=expired))

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_an_unsigned_token_is_refused(http, active_user, device):
    """Pinning the algorithm list at decode is what stops `alg: none`."""
    response = http.get(
        DIRECTORY_URL, headers=token(unsigned(live_claims(active_user, device)))
    )

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


# The point of the token below is the algorithm, not the key length PyJWT warns
# about: it is signed with this deployment's own HS256 key.
@pytest.mark.filterwarnings("ignore:The HMAC key is")
def test_a_token_signed_with_another_algorithm_is_refused(http, active_user, device):
    """The decode pins one algorithm. A verifier that accepts whatever the header
    names lets an attacker choose the family the signature is checked against."""
    access = jwt.encode(
        live_claims(active_user, device), settings.JWT_SIGNING_KEY, algorithm="HS512"
    )

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_a_token_signed_with_another_key_is_refused(http, active_user, device):
    access = jwt.encode(
        live_claims(active_user, device),
        "a-different-signing-key-of-at-least-32-bytes",
        algorithm="HS256",
    )

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


@pytest.mark.parametrize(
    "claim", ["exp", "iat", "jti", "typ", "scope", "user_id", "device_id", "tgen"]
)
def test_a_token_missing_a_required_claim_is_refused(http, active_user, device, claim):
    """The library skips a check on an absent claim, so a decode without the
    require list would accept a token that simply omits what the code reads."""
    claims = live_claims(active_user, device)
    del claims[claim]

    response = http.get(DIRECTORY_URL, headers=token(signed(claims)))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_an_unknown_scope_is_refused(http, active_user, device):
    access = signed(live_claims(active_user, device, scope="root"))

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_a_token_cannot_name_another_accounts_device(http, active_user, device, bob):
    """The device is looked up by (id, user_id) together, so a token that names a
    device it does not own finds no row."""
    access = signed(live_claims(bob, device))

    response = http.get(DIRECTORY_URL, headers=token(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


class TestBothStacksAgree:
    """Invariant 13: both stacks accept the same tokens, and a token one stack
    revokes is dead on the other.

    `voicerooms` is the REST Framework half now that `devices` and `messaging`
    have moved; run 05 takes the last of it and this class with it.
    """

    @staticmethod
    def create_room(api, access):
        return api.post(
            ROOMS_URL,
            {"name_blob": base64.b64encode(b"n" * min(NAME_BUCKETS)).decode()},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {access}",
        )

    def test_one_token_opens_both_surfaces(self, http, api, active_user, device):
        access, _refresh = issue_full(active_user, device)

        assert http.get(DIRECTORY_URL, headers=token(access)).status_code == 200
        assert self.create_room(api, access).status_code == 201

    def test_a_logout_on_one_surface_ends_the_other(self, http, api, active_user, device):
        access, _refresh = issue_full(active_user, device)

        assert http.post("/api/v1/auth/logout", headers=token(access)).status_code == 204

        response = self.create_room(api, access)
        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_a_revocation_on_one_surface_ends_the_other(
        self, http, api, active_user, device
    ):
        """Deleting a device is a FastAPI route; the token it kills is one the
        REST Framework half verifies through the same two counters."""
        access, _refresh = issue_full(active_user, device)
        other = issue_full(active_user, device)[0]

        assert (
            http.delete(f"{DEVICES_URL}/{device.id}", headers=token(other)).status_code
            == 204
        )

        response = self.create_room(api, access)
        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"
