"""A register-scope token's only power is `POST /me/devices`.

`require_register_or_full` is what admits one, and it is declared on that route
alone; every other device route declares `require_full_device`, which refuses it.
Without that split, a ten-minute register token could revoke devices.
"""

import pytest

from devices.models import Device

from .conftest import DEVICES_URL, label_blob, pubkey, register_payload

pytestmark = pytest.mark.django_db(transaction=True)


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
        "peer device list": ("get", f"/api/v1/users/{user_id}/devices", None),
        "claim prekey bundles": ("post", f"/api/v1/users/{user_id}/keys/claim", {}),
    }


@pytest.mark.parametrize("name", list(endpoints("d", "u")))
def test_a_register_scope_token_reaches_no_device_endpoint_but_registration(
    http, active_user, device, register_bearer, name
):
    method, url, body = endpoints(device.id, active_user.id)[name]
    headers = register_bearer(active_user)

    response = (
        getattr(http, method)(url, json=body, headers=headers)
        if body is not None
        else getattr(http, method)(url, headers=headers)
    )

    assert response.status_code == 403, f"{name} admitted a register-scope token"
    assert response.json()["code"] == "scope_forbidden"


def test_a_register_scope_token_cannot_revoke_a_device(
    http, active_user, device, register_bearer
):
    """The headline case, called out on its own because it is destructive."""
    http.delete(f"{DEVICES_URL}/{device.id}", headers=register_bearer(active_user))

    device.refresh_from_db()
    assert device.revoked_date is None
    assert Device.objects.filter(id=device.id, revoked_date__isnull=True).exists()


def test_the_same_token_is_still_accepted_for_registration(
    http, active_user, register_bearer
):
    """Guards the guard: if the token were simply invalid, the parametrised test
    above would pass for the wrong reason."""
    response = http.post(
        DEVICES_URL, json=register_payload(), headers=register_bearer(active_user)
    )

    assert response.status_code == 201


@pytest.mark.parametrize("name", list(endpoints("d", "u")))
def test_a_full_scope_token_reaches_every_device_endpoint(
    http, active_user, device, bearer, name
):
    """Guards the guard above: without this, the parametrised refusal would pass
    just as well against a router that admitted nothing at all. Only the scope is
    asserted — what each endpoint then makes of a minimal body is its own file's
    business."""
    method, url, body = endpoints(device.id, active_user.id)[name]
    headers = bearer(active_user, device)

    response = (
        getattr(http, method)(url, json=body, headers=headers)
        if body is not None
        else getattr(http, method)(url, headers=headers)
    )

    assert response.status_code != 403, f"{name} refused a full-scope token"
    if response.content:
        assert response.json().get("code") != "scope_forbidden"


@pytest.mark.parametrize("name", list(endpoints("d", "u")))
def test_no_device_endpoint_answers_without_a_token(http, active_user, device, name):
    """The whole surface, including the registration route the scope split exists
    to single out: an absent header is a 401 with the challenge, never a 403 and
    never a body."""
    method, url, body = endpoints(device.id, active_user.id)[name]

    response = (
        getattr(http, method)(url, json=body)
        if body is not None
        else getattr(http, method)(url)
    )

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"
    assert response.headers["www-authenticate"] == "Bearer"


def test_registration_itself_refuses_an_absent_token(http, active_user):
    """The one route a register-scope token reaches still needs one."""
    response = http.post(DEVICES_URL, json=register_payload())

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"
