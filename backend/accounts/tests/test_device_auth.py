import pytest
from django.urls import reverse
from rest_framework.response import Response
from rest_framework.test import APIRequestFactory
from rest_framework.views import APIView

from accounts.tokens import issue_full, issue_register_scope

pytestmark = pytest.mark.django_db


@pytest.fixture
def protected_url():
    return reverse("user-directory")


def bearer(access):
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


def test_a_live_device_token_is_accepted(api, active_user, device, protected_url):
    access, _ = issue_full(active_user, device)

    assert api.get(protected_url, **bearer(access)).status_code == 200


def test_revoking_a_device_rejects_its_outstanding_access_token(
    api, active_user, device, protected_url
):
    access, _ = issue_full(active_user, device)
    device.revoked_date = "2026-01-01"
    device.save(update_fields=["revoked_date"])

    response = api.get(protected_url, **bearer(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_bumping_token_generation_rejects_outstanding_access_tokens(
    api, active_user, device, protected_url
):
    access, _ = issue_full(active_user, device)
    device.token_generation += 1
    device.save(update_fields=["token_generation"])

    response = api.get(protected_url, **bearer(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_deleting_the_device_rejects_its_token(
    api, active_user, device, protected_url
):
    access, _ = issue_full(active_user, device)
    device.delete()

    response = api.get(protected_url, **bearer(access))

    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_deactivating_the_account_rejects_its_tokens(
    api, active_user, device, protected_url
):
    access, _ = issue_full(active_user, device)
    active_user.is_active = False
    active_user.save(update_fields=["is_active"])

    response = api.get(protected_url, **bearer(access))

    assert response.status_code in {401, 403}


@pytest.mark.parametrize("method, url_name, args", [
    ("get", "user-directory", []),
    ("get", "user-profile", ["11111111-1111-1111-1111-111111111111"]),
    ("get", "my-profile", []),
    ("put", "my-profile", []),
    ("post", "logout", []),
])
def test_register_scope_token_reaches_no_endpoint_in_this_phase(
    api, active_user, method, url_name, args
):
    # §A8: "`register`-scope tokens are accepted **only** by `POST /me/devices`",
    # which does not exist yet. DeviceJWTAuthentication *authenticates* these tokens,
    # so IsAuthenticated alone would let every one of these through — the scope check
    # is what holds the line.
    access = issue_register_scope(active_user)

    response = getattr(api, method)(reverse(url_name, args=args), **bearer(access))

    assert response.status_code == 403
    assert response.json()["code"] == "scope_forbidden"


def test_anonymous_requests_are_rejected(api, protected_url):
    assert api.get(protected_url).status_code == 401


def test_a_view_relying_on_project_defaults_is_closed_to_register_scope(active_user):
    """Phases 3-8 add endpoints. One that inherits DEFAULT_PERMISSION_CLASSES and
    forgets the scope check must still fail closed (§A8), rather than depending on
    every future author remembering."""

    class DefaultsOnlyView(APIView):
        def get(self, request):
            return Response({"reached": True})

    request = APIRequestFactory().get(
        "/", HTTP_AUTHORIZATION=f"Bearer {issue_register_scope(active_user)}")

    response = DefaultsOnlyView.as_view()(request)

    assert response.status_code == 403
