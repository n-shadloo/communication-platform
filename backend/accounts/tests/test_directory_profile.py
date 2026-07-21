import base64

import pytest
from django.urls import reverse

from accounts.models import ProfileBlob, User
from accounts.tokens import issue_full
from conftest import PASSWORD
from core.buckets import PROFILE_BUCKETS

pytestmark = pytest.mark.django_db


@pytest.fixture
def headers(active_user, device):
    access, _ = issue_full(active_user, device)
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


def blob_of(nbytes, fill=b"\x00"):
    return base64.b64encode(fill * nbytes).decode()


class TestDirectory:
    def test_lists_only_activated_accounts(self, api, active_user, headers):
        User.objects.create_user(username="pending", password=PASSWORD)
        User.objects.create_user(username="carol", password=PASSWORD, is_active=True)

        response = api.get(reverse("user-directory"), **headers)

        usernames = [entry["username"] for entry in response.json()["users"]]
        assert usernames == ["alice", "carol"]

    def test_entries_carry_nothing_but_id_and_username(self, api, active_user, headers):
        response = api.get(reverse("user-directory"), **headers)

        assert set(response.json()["users"][0]) == {"user_id", "username"}

    def test_listing_is_a_constant_number_of_queries(
        self, api, active_user, headers, django_assert_num_queries
    ):
        for index in range(25):
            User.objects.create_user(username=f"user{index:02d}", password=PASSWORD,
                                     is_active=True)

        # 1 user lookup + 1 device check (DeviceJWTAuthentication) + 1 directory read.
        with django_assert_num_queries(3):
            response = api.get(reverse("user-directory"), **headers)

        assert len(response.json()["users"]) == 26


class TestReadProfile:
    def test_returns_the_stored_blob_and_version(self, api, active_user, headers):
        raw = b"\x01" * PROFILE_BUCKETS[0]
        ProfileBlob.objects.create(user=active_user, blob=raw, version=3)

        response = api.get(
            reverse("user-profile", args=[active_user.id]), **headers
        )

        assert response.status_code == 200
        assert base64.b64decode(response.json()["blob"]) == raw
        assert response.json()["version"] == 3

    def test_own_profile_is_readable(self, api, active_user, headers):
        raw = b"\x03" * PROFILE_BUCKETS[0]
        ProfileBlob.objects.create(user=active_user, blob=raw, version=2)

        response = api.get(reverse("my-profile"), **headers)

        assert response.status_code == 200
        assert base64.b64decode(response.json()["blob"]) == raw
        assert response.json()["version"] == 2

    def test_missing_profile_is_a_404(self, api, active_user, headers):
        response = api.get(
            reverse("user-profile", args=[active_user.id]), **headers
        )

        assert response.status_code == 404
        assert response.json()["code"] == "not_found"

    def test_inactive_users_profile_is_not_served(self, api, active_user, headers):
        pending = User.objects.create_user(username="pending", password=PASSWORD)
        ProfileBlob.objects.create(user=pending, blob=b"\x02" * PROFILE_BUCKETS[0],
                                   version=1)

        response = api.get(reverse("user-profile", args=[pending.id]), **headers)

        assert response.status_code == 404


class TestWriteProfile:
    def test_stores_a_bucket_sized_blob(self, api, active_user, headers):
        response = api.put(reverse("my-profile"),
                           {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 1},
                           format="json", **headers)

        assert response.status_code == 200
        stored = ProfileBlob.objects.get(user=active_user)
        assert len(bytes(stored.blob)) == PROFILE_BUCKETS[0]
        assert stored.version == 1

    @pytest.mark.parametrize("size", [
        PROFILE_BUCKETS[0] - 1,
        PROFILE_BUCKETS[0] + 1,
        PROFILE_BUCKETS[-1] + 1,
        1,
    ])
    def test_wrong_length_blob_is_bad_bucket(self, api, active_user, headers, size):
        response = api.put(reverse("my-profile"),
                           {"blob": blob_of(size), "version": 1},
                           format="json", **headers)

        assert response.status_code == 400
        assert response.json()["code"] == "bad_bucket"
        assert not ProfileBlob.objects.filter(user=active_user).exists()

    def test_non_base64_blob_is_bad_bucket(self, api, active_user, headers):
        response = api.put(reverse("my-profile"),
                           {"blob": "definitely not base64 !!", "version": 1},
                           format="json", **headers)

        assert response.status_code == 400
        assert response.json()["code"] == "bad_bucket"

    def test_bad_bucket_response_never_echoes_the_payload(
        self, api, active_user, headers
    ):
        payload = blob_of(PROFILE_BUCKETS[0] + 1, fill=b"\xab")

        response = api.put(reverse("my-profile"), {"blob": payload, "version": 1},
                           format="json", **headers)

        assert payload not in response.content.decode()

    def test_version_must_increase(self, api, active_user, headers):
        url = reverse("my-profile")
        api.put(url, {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 5},
                format="json", **headers)

        response = api.put(url, {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 5},
                           format="json", **headers)

        assert response.status_code == 409
        assert response.json()["code"] == "stale_version"

    def test_a_higher_version_overwrites(self, api, active_user, headers):
        url = reverse("my-profile")
        api.put(url, {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 1},
                format="json", **headers)

        response = api.put(url, {"blob": blob_of(PROFILE_BUCKETS[1], fill=b"\x09"),
                                 "version": 2},
                           format="json", **headers)

        assert response.status_code == 200
        stored = ProfileBlob.objects.get(user=active_user)
        assert stored.version == 2
        assert len(bytes(stored.blob)) == PROFILE_BUCKETS[1]

    def test_a_write_reads_the_row_once(self, api, active_user, headers,
                                        django_assert_num_queries):
        """The locked version check and the write must not each SELECT the row.
        2 auth + savepoint + locked read + UPDATE + release."""
        url = reverse("my-profile")
        api.put(url, {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 1},
                format="json", **headers)

        with django_assert_num_queries(6):
            response = api.put(url, {"blob": blob_of(PROFILE_BUCKETS[0]),
                                     "version": 2}, format="json", **headers)

        assert response.status_code == 200

    def test_unknown_fields_are_rejected(self, api, active_user, headers):
        response = api.put(reverse("my-profile"),
                           {"blob": blob_of(PROFILE_BUCKETS[0]), "version": 1,
                            "user_id": "someone-else"},
                           format="json", **headers)

        assert response.status_code == 400
        assert response.json()["code"] == "invalid_request"
