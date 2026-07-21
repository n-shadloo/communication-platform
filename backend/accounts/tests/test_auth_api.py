from unittest import mock

import pytest
from django.contrib.auth.hashers import check_password
from django.urls import reverse

from accounts.models import User
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.tokens import issue_full
from accounts.views import _DUMMY_HASH
from conftest import PASSWORD
from devices.models import Device

pytestmark = pytest.mark.django_db

GOOD_PASSWORD = "a-sufficiently-long-passphrase"


@pytest.fixture
def register_url():
    return reverse("register")


@pytest.fixture
def login_url():
    return reverse("login")


class TestRegister:
    def test_creates_an_inactive_account(self, api, register_url):
        response = api.post(register_url,
                            {"username": "bob", "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 201
        assert set(response.json()) == {"user_id"}
        user = User.objects.get(id=response.json()["user_id"])
        assert user.is_active is False

    def test_username_is_normalised_to_lowercase(self, api, register_url):
        response = api.post(register_url,
                            {"username": "BoB", "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 201
        assert User.objects.get(id=response.json()["user_id"]).username == "bob"

    def test_duplicate_username_is_reported_inline(self, api, register_url):
        api.post(register_url, {"username": "bob", "password": GOOD_PASSWORD},
                 format="json")

        response = api.post(register_url,
                            {"username": "bob", "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "username_taken"

    def test_case_variant_collides_with_an_existing_username(self, api, register_url):
        api.post(register_url, {"username": "bob", "password": GOOD_PASSWORD},
                 format="json")

        response = api.post(register_url,
                            {"username": "BOB", "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "username_taken"

    @pytest.mark.parametrize("username", ["ab", "x" * 33, "has space", "Ünicode", "dash-es"])
    def test_username_must_match_the_model_validator(self, api, register_url, username):
        response = api.post(register_url,
                            {"username": username, "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"

    @pytest.mark.parametrize("password", ["short", "password123"])
    def test_password_must_pass_django_validators(self, api, register_url, password):
        response = api.post(register_url,
                            {"username": "bob", "password": password},
                            format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"
        assert not User.objects.filter(username="bob").exists()

    def test_unknown_fields_are_rejected(self, api, register_url):
        response = api.post(register_url,
                            {"username": "bob", "password": GOOD_PASSWORD,
                             "is_staff": True},
                            format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"

    # Both are rejected — one for length, one for being common — so there is always an
    # error body that could have leaked the value.
    @pytest.mark.parametrize("password", ["zzqqxvw", "password123"])
    def test_error_never_echoes_the_submitted_password(self, api, register_url,
                                                       password):
        response = api.post(register_url,
                            {"username": "bob", "password": password},
                            format="json")

        assert response.status_code == 400
        assert password not in response.content.decode()


class TestLogin:
    def test_unknown_username_still_pays_for_a_dummy_argon2_verify(self, api, login_url):
        with mock.patch("accounts.views.check_password",
                        wraps=check_password) as verify:
            response = api.post(login_url,
                                {"username": "ghost", "password": GOOD_PASSWORD},
                                format="json")

        assert response.status_code == 401
        assert verify.call_count == 1
        # Verified against a real Argon2id hash, so the work matches a live account.
        assert verify.call_args.args[1] == _DUMMY_HASH
        assert _DUMMY_HASH.startswith("argon2$argon2id$")

    def test_unknown_user_and_wrong_password_are_indistinguishable(
        self, api, login_url, active_user
    ):
        unknown = api.post(login_url,
                           {"username": "ghost", "password": GOOD_PASSWORD},
                           format="json")
        wrong = api.post(login_url,
                         {"username": "alice", "password": "the-wrong-passphrase"},
                         format="json")

        assert unknown.status_code == wrong.status_code == 401
        assert unknown.json() == wrong.json()
        assert unknown.json()["code"] == "invalid_credentials"

    def test_inactive_account_is_told_to_wait(self, api, login_url):
        User.objects.create_user(username="bob", password=GOOD_PASSWORD)

        response = api.post(login_url,
                            {"username": "bob", "password": GOOD_PASSWORD},
                            format="json")

        assert response.status_code == 403
        assert response.json()["code"] == "account_inactive"

    def test_activation_state_leaks_only_after_the_password_is_proven(
        self, api, login_url
    ):
        User.objects.create_user(username="bob", password=GOOD_PASSWORD)

        response = api.post(login_url,
                            {"username": "bob", "password": "the-wrong-passphrase"},
                            format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "invalid_credentials"

    def test_without_a_device_only_a_register_scope_token_is_issued(
        self, api, login_url, active_user
    ):
        response = api.post(login_url,
                            {"username": "alice", "password": PASSWORD},
                            format="json")

        body = response.json()
        assert response.status_code == 200
        assert body["scope"] == "register"
        assert set(body) == {"access", "user_id", "scope"}
        assert "refresh" not in body

    def test_with_a_live_device_a_full_scope_pair_is_issued(
        self, api, login_url, active_user, device
    ):
        response = api.post(
            login_url,
            {"username": "alice", "password": PASSWORD, "device_id": str(device.id)},
            format="json",
        )

        body = response.json()
        assert response.status_code == 200
        assert body["scope"] == "full"
        assert body["device_id"] == str(device.id)
        assert body["access"] and body["refresh"]

    def test_revoked_device_falls_back_to_register_scope(
        self, api, login_url, active_user, device
    ):
        device.revoked_date = "2026-01-01"
        device.save(update_fields=["revoked_date"])

        response = api.post(
            login_url,
            {"username": "alice", "password": PASSWORD, "device_id": str(device.id)},
            format="json",
        )

        assert response.json()["scope"] == "register"

    # Login parses anonymous input, so a type confusion here is an unauthenticated 500.
    @pytest.mark.parametrize("payload", [
        {"username": {"$ne": None}, "password": GOOD_PASSWORD},
        {"username": ["alice"], "password": GOOD_PASSWORD},
        {"username": "alice", "password": GOOD_PASSWORD, "device_id": "not-a-uuid"},
    ])
    def test_malformed_input_is_rejected_without_a_server_error(
        self, api, login_url, payload
    ):
        response = api.post(login_url, payload, format="json")

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"

    def test_a_device_belonging_to_another_user_is_never_honoured(
        self, api, login_url, active_user
    ):
        intruder = User.objects.create_user(username="mallory", password=PASSWORD,
                                            is_active=True)
        their_device = Device.objects.create(
            user=intruder, ik_pub=b"ik", spk_id=1, spk_pub=b"spk", spk_sig=b"sig",
            registration_id=7,
        )

        response = api.post(
            login_url,
            {"username": "alice", "password": PASSWORD,
             "device_id": str(their_device.id)},
            format="json",
        )

        assert response.json()["scope"] == "register"


class TestRefresh:
    def refresh_for(self, user, device):
        _access, refresh = issue_full(user, device)
        return refresh

    def test_rotation_returns_a_new_pair_and_retires_the_old_refresh(
        self, api, active_user, device
    ):
        url = reverse("refresh")
        original = self.refresh_for(active_user, device)

        rotated = api.post(url, {"refresh": original}, format="json")
        assert rotated.status_code == 200
        assert rotated.json()["refresh"] != original

        replayed = api.post(url, {"refresh": original}, format="json")
        assert replayed.status_code == 401

    def test_revoked_device_kills_the_refresh_immediately(self, api, active_user, device):
        refresh = self.refresh_for(active_user, device)
        device.revoked_date = "2026-01-01"
        device.save(update_fields=["revoked_date"])

        response = api.post(reverse("refresh"), {"refresh": refresh}, format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_bumping_token_generation_kills_the_refresh(self, api, active_user, device):
        refresh = self.refresh_for(active_user, device)
        device.token_generation += 1
        device.save(update_fields=["token_generation"])

        response = api.post(reverse("refresh"), {"refresh": refresh}, format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_rotation_costs_a_fixed_number_of_queries(
        self, api, active_user, device, django_assert_num_queries
    ):
        """Refresh runs every <=15 min per device. The device row is fetched with
        .only(...) over a select_related join, so touching a column outside that set
        (a key blob, the username) would silently add a deferred load per refresh.
        1 blacklist check + 1 device join + 6 SimpleJWT blacklist internals
        (tokens.py:292 fetches the user unconditionally) + 1 outstanding insert."""
        refresh = self.refresh_for(active_user, device)

        with django_assert_num_queries(9):
            response = api.post(reverse("refresh"), {"refresh": refresh},
                                format="json")

        assert response.status_code == 200

    def test_a_refresh_without_full_scope_is_refused(self, api, active_user):
        # A bare SimpleJWT refresh carries no device binding; it must never rotate
        # up into a full-scope pair (§A8).
        bare = RefreshToken.for_user(active_user)

        response = api.post(reverse("refresh"), {"refresh": str(bare)}, format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_a_refresh_cannot_borrow_another_users_device(self, api, active_user, device):
        # device belongs to active_user; the token claims to be someone else's.
        intruder = User.objects.create_user(username="mallory", password=PASSWORD,
                                            is_active=True)
        forged = RefreshToken.for_user(intruder)
        forged["device_id"] = str(device.id)
        forged["tgen"] = device.token_generation
        forged["scope"] = "full"

        response = api.post(reverse("refresh"), {"refresh": str(forged)}, format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"

    def test_deactivated_account_cannot_refresh(self, api, active_user, device):
        refresh = self.refresh_for(active_user, device)
        active_user.is_active = False
        active_user.save(update_fields=["is_active"])

        response = api.post(reverse("refresh"), {"refresh": refresh}, format="json")

        assert response.status_code == 401
        assert response.json()["code"] == "token_revoked"


class TestLogout:
    def test_blacklists_the_callers_refresh_token(
        self, api, active_user, device, auth_headers
    ):
        access, refresh = issue_full(active_user, device)

        response = api.post(reverse("logout"), {"refresh": refresh}, format="json",
                            HTTP_AUTHORIZATION=f"Bearer {access}")

        assert response.status_code == 205
        replay = api.post(reverse("refresh"), {"refresh": refresh}, format="json")
        assert replay.status_code == 401

    def test_cannot_blacklist_another_accounts_refresh_token(
        self, api, active_user, device
    ):
        victim = User.objects.create_user(username="victim", password=PASSWORD,
                                          is_active=True)
        victim_device = Device.objects.create(
            user=victim, ik_pub=b"ik", spk_id=1, spk_pub=b"spk", spk_sig=b"sig",
            registration_id=9,
        )
        _victim_access, victim_refresh = issue_full(victim, victim_device)
        attacker_access, _ = issue_full(active_user, device)

        response = api.post(reverse("logout"), {"refresh": victim_refresh},
                            format="json",
                            HTTP_AUTHORIZATION=f"Bearer {attacker_access}")

        assert response.status_code == 205
        # The victim's token still works: logout is not a cross-account weapon.
        still_valid = api.post(reverse("refresh"), {"refresh": victim_refresh},
                               format="json")
        assert still_valid.status_code == 200

    def test_requires_authentication(self, api, active_user, device):
        _access, refresh = issue_full(active_user, device)

        response = api.post(reverse("logout"), {"refresh": refresh}, format="json")

        assert response.status_code == 401
