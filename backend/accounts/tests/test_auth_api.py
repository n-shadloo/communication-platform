"""Registration, login, and the token lifecycle.

Every route here answers through FastAPI. The token semantics are ADR-0006's:
no token is stored, and revocation is the two generation counters on the device
row. `token_generation` kills every token of the device; `refresh_generation`
kills every refresh token issued before the last rotation.
"""

from unittest import mock

import pytest
from django.contrib.auth.hashers import check_password

from accounts.models import User
from accounts.services import DUMMY_HASH
from api.auth import issue_full, issue_register_scope
from conftest import PASSWORD
from devices.models import Device

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)

GOOD_PASSWORD = "a-sufficiently-long-passphrase"
REGISTER_URL = "/api/v1/auth/register"
LOGIN_URL = "/api/v1/auth/login"
REFRESH_URL = "/api/v1/auth/refresh"
LOGOUT_URL = "/api/v1/auth/logout"
DIRECTORY_URL = "/api/v1/users"


class TestRegister:
    def test_creates_an_inactive_account(self, http):
        response = http.post(
            REGISTER_URL, json={"username": "bob", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 201
        assert set(response.json()) == {"user_id"}
        user = User.objects.get(id=response.json()["user_id"])
        assert user.is_active is False

    def test_username_is_normalised_to_lowercase(self, http):
        response = http.post(
            REGISTER_URL, json={"username": "BoB", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 201
        assert User.objects.get(id=response.json()["user_id"]).username == "bob"

    def test_duplicate_username_is_a_conflict(self, http):
        http.post(REGISTER_URL, json={"username": "bob", "password": GOOD_PASSWORD})

        response = http.post(
            REGISTER_URL, json={"username": "bob", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 409
        assert response.json()["code"] == "username_taken"

    def test_case_variant_collides_with_an_existing_username(self, http):
        http.post(REGISTER_URL, json={"username": "bob", "password": GOOD_PASSWORD})

        response = http.post(
            REGISTER_URL, json={"username": "BOB", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 409
        assert response.json()["code"] == "username_taken"

    @pytest.mark.parametrize(
        "username", ["ab", "x" * 33, "has space", "Ünicode", "dash-es"]
    )
    def test_username_must_match_the_model_validator(self, http, username):
        response = http.post(
            REGISTER_URL, json={"username": username, "password": GOOD_PASSWORD}
        )

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"
        assert set(response.json()["detail"]) == {"username"}

    @pytest.mark.parametrize("password", ["short", "password123"])
    def test_password_must_pass_django_validators(self, http, password):
        response = http.post(REGISTER_URL, json={"username": "bob", "password": password})

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"
        assert not User.objects.filter(username="bob").exists()

    def test_unknown_fields_are_rejected(self, http):
        response = http.post(
            REGISTER_URL,
            json={"username": "bob", "password": GOOD_PASSWORD, "is_staff": True},
        )

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"

    # Both are rejected — one for length, one for being common — so there is
    # always an error body that could have leaked the value.
    @pytest.mark.parametrize("password", ["zzqqxvw", "password123"])
    def test_error_never_echoes_the_submitted_password(self, http, password):
        response = http.post(REGISTER_URL, json={"username": "bob", "password": password})

        assert response.status_code == 400
        assert password not in response.text


class TestLogin:
    def test_unknown_username_still_pays_for_a_dummy_argon2_verify(self, http):
        with mock.patch(
            "accounts.services.check_password", wraps=check_password
        ) as verify:
            response = http.post(
                LOGIN_URL, json={"username": "ghost", "password": GOOD_PASSWORD}
            )

        assert response.status_code == 401
        assert verify.call_count == 1
        # Verified against a real Argon2id hash, so the work matches a live account.
        assert verify.call_args.args[1] == DUMMY_HASH
        assert DUMMY_HASH.startswith("argon2$argon2id$")

    def test_unknown_user_and_wrong_password_are_indistinguishable(
        self, http, active_user
    ):
        unknown = http.post(
            LOGIN_URL, json={"username": "ghost", "password": GOOD_PASSWORD}
        )
        wrong = http.post(
            LOGIN_URL, json={"username": "alice", "password": "the-wrong-passphrase"}
        )

        assert unknown.status_code == wrong.status_code == 401
        assert unknown.json() == wrong.json()
        assert unknown.json()["code"] == "invalid_credentials"

    def test_inactive_account_is_told_to_wait(self, http):
        User.objects.create_user(username="bob", password=GOOD_PASSWORD)

        response = http.post(
            LOGIN_URL, json={"username": "bob", "password": GOOD_PASSWORD}
        )

        assert response.status_code == 403
        assert response.json()["code"] == "account_inactive"

    def test_activation_state_leaks_only_after_the_password_is_proven(self, http):
        User.objects.create_user(username="bob", password=GOOD_PASSWORD)

        response = http.post(
            LOGIN_URL, json={"username": "bob", "password": "the-wrong-passphrase"}
        )

        assert response.status_code == 401
        assert response.json()["code"] == "invalid_credentials"

    def test_without_a_device_only_a_register_scope_token_is_issued(
        self, http, active_user
    ):
        response = http.post(LOGIN_URL, json={"username": "alice", "password": PASSWORD})

        body = response.json()
        assert response.status_code == 200
        assert body["scope"] == "register"
        assert set(body) == {"access", "user_id", "scope"}

    def test_with_a_live_device_a_full_scope_pair_is_issued(
        self, http, active_user, device
    ):
        response = http.post(
            LOGIN_URL,
            json={
                "username": "alice",
                "password": PASSWORD,
                "device_id": str(device.id),
            },
        )

        body = response.json()
        assert response.status_code == 200
        assert body["scope"] == "full"
        assert body["device_id"] == str(device.id)
        assert body["access"] and body["refresh"]

    def test_login_retires_the_refresh_tokens_the_device_already_held(
        self, http, active_user, device
    ):
        """A login advances the refresh generation, so a refresh token minted
        before it is a replay and dies with the rest of its family."""
        _access, older = issue_full(active_user, device)

        http.post(
            LOGIN_URL,
            json={
                "username": "alice",
                "password": PASSWORD,
                "device_id": str(device.id),
            },
        )

        device.refresh_from_db()
        assert device.refresh_generation == 2
        replay = http.post(REFRESH_URL, json={"refresh": older})
        assert replay.status_code == 401
        assert replay.json()["code"] == "token_revoked"

    def test_revoked_device_falls_back_to_register_scope(self, http, active_user, device):
        device.revoked_date = "2026-01-01"
        device.save(update_fields=["revoked_date"])

        response = http.post(
            LOGIN_URL,
            json={
                "username": "alice",
                "password": PASSWORD,
                "device_id": str(device.id),
            },
        )

        assert response.json()["scope"] == "register"

    # Login parses anonymous input, so a type confusion here is an
    # unauthenticated 500.
    @pytest.mark.parametrize(
        "payload",
        [
            {"username": {"$ne": None}, "password": GOOD_PASSWORD},
            {"username": ["alice"], "password": GOOD_PASSWORD},
            {"username": "alice", "password": GOOD_PASSWORD, "device_id": "not-a-uuid"},
            {"username": "alice", "password": 12345},
        ],
    )
    def test_malformed_input_is_rejected_without_a_server_error(self, http, payload):
        response = http.post(LOGIN_URL, json=payload)

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"

    def test_a_device_belonging_to_another_user_is_never_honoured(
        self, http, active_user
    ):
        intruder = User.objects.create_user(
            username="mallory", password=PASSWORD, is_active=True
        )
        their_device = Device.objects.create(
            user=intruder,
            ik_pub=b"ik",
            spk_id=1,
            spk_pub=b"spk",
            spk_sig=b"sig",
            registration_id=7,
        )

        response = http.post(
            LOGIN_URL,
            json={
                "username": "alice",
                "password": PASSWORD,
                "device_id": str(their_device.id),
            },
        )

        assert response.json()["scope"] == "register"
        their_device.refresh_from_db()
        assert their_device.refresh_generation == 1


class TestRefresh:
    def test_rotation_returns_a_new_pair_and_advances_the_generation(
        self, http, active_user, device
    ):
        _access, original = issue_full(active_user, device)

        rotated = http.post(REFRESH_URL, json={"refresh": original})

        assert rotated.status_code == 200
        assert set(rotated.json()) == {"access", "refresh"}
        assert rotated.json()["refresh"] != original
        device.refresh_from_db()
        assert device.refresh_generation == 2

    def test_the_rotated_pair_still_works(self, http, active_user, device, bearer):
        _access, original = issue_full(active_user, device)
        rotated = http.post(REFRESH_URL, json={"refresh": original}).json()

        assert (
            http.get(
                DIRECTORY_URL,
                headers={"Authorization": f"Bearer {rotated['access']}"},
            ).status_code
            == 200
        )
        assert (
            http.post(REFRESH_URL, json={"refresh": rotated["refresh"]}).status_code
            == 200
        )

    def test_replaying_a_rotated_refresh_kills_the_whole_family(
        self, http, active_user, device
    ):
        """Reuse detection. The device row is the family: a stale `rgen` with a
        live `tgen` advances `token_generation`, so the access token and the
        refresh token of the newest pair die alongside the replayed one."""
        _access, original = issue_full(active_user, device)
        newest = http.post(REFRESH_URL, json={"refresh": original}).json()

        replay = http.post(REFRESH_URL, json={"refresh": original})

        assert replay.status_code == 401
        assert replay.json()["code"] == "token_revoked"
        device.refresh_from_db()
        assert device.token_generation == 2
        assert (
            http.get(
                DIRECTORY_URL, headers={"Authorization": f"Bearer {newest['access']}"}
            ).status_code
            == 401
        )
        assert (
            http.post(REFRESH_URL, json={"refresh": newest["refresh"]}).status_code == 401
        )

    def test_revoked_device_kills_the_refresh_immediately(
        self, http, active_user, device
    ):
        _access, refresh = issue_full(active_user, device)
        device.revoked_date = "2026-01-01"
        device.save(update_fields=["revoked_date"])

        response = http.post(REFRESH_URL, json={"refresh": refresh})

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_bumping_token_generation_kills_the_refresh(self, http, active_user, device):
        _access, refresh = issue_full(active_user, device)
        device.token_generation += 1
        device.save(update_fields=["token_generation"])

        response = http.post(REFRESH_URL, json={"refresh": refresh})

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_an_access_token_is_not_a_refresh_token(self, http, active_user, device):
        """Both are signed with the same key; only the `typ` claim separates
        them, and every decode pins it."""
        access, _refresh = issue_full(active_user, device)

        response = http.post(REFRESH_URL, json={"refresh": access})

        assert response.status_code == 401
        assert response.json()["code"] == "invalid_token"

    def test_a_register_scope_token_never_rotates_up(self, http, active_user):
        response = http.post(
            REFRESH_URL, json={"refresh": issue_register_scope(active_user)}
        )

        assert response.status_code == 401
        assert response.json()["code"] == "invalid_token"

    def test_a_refresh_cannot_borrow_another_users_device(
        self, http, active_user, device
    ):
        intruder = User.objects.create_user(
            username="mallory", password=PASSWORD, is_active=True
        )
        their_device = Device.objects.create(
            user=intruder,
            ik_pub=b"ik",
            spk_id=1,
            spk_pub=b"spk",
            spk_sig=b"sig",
            registration_id=8,
        )
        _access, theirs = issue_full(intruder, their_device)
        # The signature is valid; the device is simply not this account's.
        assert http.post(REFRESH_URL, json={"refresh": theirs}).status_code == 200
        their_device.delete()

        response = http.post(REFRESH_URL, json={"refresh": theirs})

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_deactivated_account_cannot_refresh(self, http, active_user, device):
        _access, refresh = issue_full(active_user, device)
        active_user.is_active = False
        active_user.save(update_fields=["is_active"])

        response = http.post(REFRESH_URL, json={"refresh": refresh})

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_a_garbage_token_is_an_invalid_token(self, http):
        response = http.post(REFRESH_URL, json={"refresh": "not-a-jwt"})

        assert response.status_code == 401
        assert response.json()["code"] == "invalid_token"


class TestLogout:
    def test_ends_every_token_of_the_calling_device(
        self, http, active_user, device, bearer
    ):
        headers = bearer(active_user, device)
        access, refresh = issue_full(active_user, device)

        response = http.post(LOGOUT_URL, headers=headers)

        assert response.status_code == 204
        assert response.content == b""
        device.refresh_from_db()
        assert device.token_generation == 2
        assert (
            http.get(
                DIRECTORY_URL, headers={"Authorization": f"Bearer {access}"}
            ).status_code
            == 401
        )
        assert http.post(REFRESH_URL, json={"refresh": refresh}).status_code == 401

    def test_takes_no_body_and_ignores_one(self, http, active_user, device, bearer):
        response = http.post(
            LOGOUT_URL, headers=bearer(active_user, device), json={"refresh": "junk"}
        )

        assert response.status_code == 204

    def test_the_presented_token_cannot_log_out_twice(
        self, http, active_user, device, bearer
    ):
        """Logout advances the token generation, so the access token that
        performed it is finished the moment it succeeds."""
        headers = bearer(active_user, device)

        assert http.post(LOGOUT_URL, headers=headers).status_code == 204

        repeat = http.post(LOGOUT_URL, headers=headers)
        assert repeat.status_code == 401
        assert repeat.json()["code"] == "token_revoked"

    def test_touches_no_other_account(self, http, active_user, device, bearer):
        victim = User.objects.create_user(
            username="victim", password=PASSWORD, is_active=True
        )
        victim_device = Device.objects.create(
            user=victim,
            ik_pub=b"ik",
            spk_id=1,
            spk_pub=b"spk",
            spk_sig=b"sig",
            registration_id=9,
        )
        _victim_access, victim_refresh = issue_full(victim, victim_device)

        assert (
            http.post(LOGOUT_URL, headers=bearer(active_user, device)).status_code == 204
        )

        assert http.post(REFRESH_URL, json={"refresh": victim_refresh}).status_code == 200

    def test_requires_authentication(self, http):
        response = http.post(LOGOUT_URL)

        assert response.status_code == 401
        assert response.json()["code"] == "unauthenticated"
        assert response.headers["www-authenticate"] == "Bearer"


class TestLoginLockout:
    """The cool-off on a login name, shared with the admin panel (`core/lockout.py`).

    The address limiter alone bounds a guesser to its rate per address, and an
    attacker with many addresses multiplies it. The name is the thing being
    attacked, so the name is what locks: five failures in fifteen minutes refuse
    the name — real or not, so the lock confirms nothing about existence — before
    the password is hashed.
    """

    def fail(self, http, username, times):
        for _ in range(times):
            response = http.post(
                LOGIN_URL, json={"username": username, "password": "the-wrong-one"}
            )
            assert response.status_code == 401

    def test_repeated_failures_lock_the_name_with_a_retry_after(self, http, active_user):
        from core.lockout import COOLOFF_SECONDS, FAILURE_THRESHOLD

        self.fail(http, "alice", FAILURE_THRESHOLD)

        # The right password now, and it is still refused.
        response = http.post(LOGIN_URL, json={"username": "alice", "password": PASSWORD})

        assert response.status_code == 429
        assert response.json()["code"] == "throttled"
        assert 0 < int(response.headers["Retry-After"]) <= COOLOFF_SECONDS

    def test_a_locked_name_never_reaches_the_password_hash(self, http, active_user):
        from core.lockout import FAILURE_THRESHOLD

        self.fail(http, "alice", FAILURE_THRESHOLD)

        with (
            mock.patch.object(User, "check_password", autospec=True) as known,
            mock.patch("accounts.services.check_password") as unknown,
        ):
            http.post(LOGIN_URL, json={"username": "alice", "password": PASSWORD})

        assert known.call_count == 0
        assert unknown.call_count == 0

    def test_the_lock_is_keyed_on_the_name_and_not_on_existence(self, http):
        """A name that exists and one that does not lock the same way, so the
        lock is not an oracle for the directory."""
        from core.lockout import FAILURE_THRESHOLD

        self.fail(http, "ghost", FAILURE_THRESHOLD)

        response = http.post(LOGIN_URL, json={"username": "ghost", "password": PASSWORD})

        assert response.status_code == 429
        assert response.json()["code"] == "throttled"

    def test_the_lock_holds_for_one_name_only(self, http, active_user, bob):
        from core.lockout import FAILURE_THRESHOLD

        self.fail(http, "alice", FAILURE_THRESHOLD)

        response = http.post(LOGIN_URL, json={"username": "bob", "password": PASSWORD})

        assert response.status_code == 200

    def test_a_successful_login_forgets_the_earlier_failures(self, http, active_user):
        from core.lockout import FAILURE_THRESHOLD

        self.fail(http, "alice", FAILURE_THRESHOLD - 1)
        assert (
            http.post(
                LOGIN_URL, json={"username": "alice", "password": PASSWORD}
            ).status_code
            == 200
        )
        self.fail(http, "alice", FAILURE_THRESHOLD - 1)

        response = http.post(LOGIN_URL, json={"username": "alice", "password": PASSWORD})

        assert response.status_code == 200

    def test_the_lock_refuses_when_redis_cannot_be_read(
        self, http, active_user, monkeypatch
    ):
        """Fails closed, like the address limiter (ADR-0010) and the admin form:
        a control whose purpose is to refuse cannot answer "allow" when it does
        not know."""
        import redis

        class Unreachable:
            def ttl(self, *args, **kwargs):
                raise redis.ConnectionError("redis is down")

        monkeypatch.setattr("core.lockout._redis", lambda: Unreachable())

        response = http.post(LOGIN_URL, json={"username": "alice", "password": PASSWORD})

        assert response.status_code == 503
        assert response.json()["code"] == "unavailable"
