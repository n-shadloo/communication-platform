"""A register-scope token's only power is `POST /me/devices`.

`DeviceJWTAuthentication` authenticates register-scope tokens, so `IsAuthenticated`
alone is satisfied by one. Every device endpoint except registration must therefore
carry the scope check; without it, a ten-minute register token could revoke devices.
"""

import pytest

from accounts.tokens import issue_register_scope
from devices.models import Device

from .conftest import DEVICES_URL, label_blob, pubkey

pytestmark = pytest.mark.django_db


def bearer(access):
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


@pytest.fixture
def register_headers(active_user):
    return bearer(issue_register_scope(active_user))


def endpoints(device_id, user_id):
    return {
        "publish identity": ("put", "/api/v1/me/identity", {}),
        "peer identity": ("get", f"/api/v1/users/{user_id}/identity", None),
        "append devicelog": ("post", "/api/v1/me/devicelog", {}),
        "peer devicelog": ("get", f"/api/v1/users/{user_id}/devicelog", None),
        "own device list": ("get", DEVICES_URL, None),
        "relabel a device": (
            "put",
            f"{DEVICES_URL}/{device_id}",
            {"label_blob": label_blob()},
        ),
        "revoke a device": ("delete", f"{DEVICES_URL}/{device_id}", None),
        "replenish prekeys": (
            "put",
            f"{DEVICES_URL}/{device_id}/prekeys",
            {"otpks": [{"key_id": 1, "pub": pubkey()}]},
        ),
        "prekey count": ("get", f"{DEVICES_URL}/{device_id}/prekeys/count", None),
        "upload keypackages": (
            "put",
            f"{DEVICES_URL}/{device_id}/keypackages",
            {"keypackages": []},
        ),
        "keypackage count": ("get", f"{DEVICES_URL}/{device_id}/keypackages/count", None),
        "peer device list": ("get", f"/api/v1/users/{user_id}/devices", None),
        "claim prekey bundles": ("post", f"/api/v1/users/{user_id}/keys/claim", {}),
        "claim key packages": ("post", f"/api/v1/users/{user_id}/keypackages/claim", {}),
    }


@pytest.mark.parametrize("name", list(endpoints("d", "u")))
def test_a_register_scope_token_reaches_no_device_endpoint_but_registration(
    api, active_user, device, register_headers, name
):
    method, url, body = endpoints(device.id, active_user.id)[name]
    kwargs = {"format": "json", **register_headers}

    response = (
        getattr(api, method)(url, body, **kwargs)
        if body is not None
        else getattr(api, method)(url, **register_headers)
    )

    assert response.status_code == 403, f"{name} admitted a register-scope token"
    assert response.json()["code"] == "scope_forbidden"


def test_a_register_scope_token_cannot_revoke_a_device(
    api, active_user, device, register_headers
):
    """The headline case, called out on its own because it is destructive."""
    api.delete(f"{DEVICES_URL}/{device.id}", **register_headers)

    device.refresh_from_db()
    assert device.revoked_date is None
    assert Device.objects.filter(id=device.id, revoked_date__isnull=True).exists()


def test_the_same_token_is_still_accepted_for_registration(api, register_headers):
    """Guards the guard: if the token were simply invalid, the parametrised test above
    would pass for the wrong reason."""
    from .conftest import register_payload

    response = api.post(
        DEVICES_URL, register_payload(), format="json", **register_headers
    )

    assert response.status_code == 201
