"""Bundle contents and single consumption in the sequential case. The concurrent
case is test_claim_race.py."""

import base64

import pytest
from django.utils import timezone

from devices.models import KeyPackage, OneTimePrekey

from .conftest import make_device, stock_keypackages, stock_prekeys

pytestmark = pytest.mark.django_db


def claim_url(user_id):
    return f"/api/v1/users/{user_id}/keys/claim"


def kp_claim_url(user_id):
    return f"/api/v1/users/{user_id}/keypackages/claim"


def test_a_bundle_carries_the_public_x3dh_material(
    api, active_user, device, auth_headers, peer, peer_device
):
    stock_prekeys(peer_device, 1, start=5)

    response = api.post(
        claim_url(peer.id), {}, format="json", **auth_headers(active_user, device)
    )

    assert response.status_code == 200
    bundle = response.json()["bundles"][0]
    assert set(bundle) == {
        "device_id",
        "registration_id",
        "ik_pub",
        "spk_id",
        "spk_pub",
        "spk_sig",
        "cross_sig",
        "bundle_version",
        "otpk",
    }
    assert base64.b64decode(bundle["ik_pub"]) == bytes(peer_device.ik_pub)
    assert bundle["otpk"]["key_id"] == 5


def test_claiming_consumes_the_one_time_prekey(
    api, active_user, device, auth_headers, peer, peer_device
):
    stock_prekeys(peer_device, 1)
    headers = auth_headers(active_user, device)

    api.post(claim_url(peer.id), {}, format="json", **headers)

    assert OneTimePrekey.objects.filter(device=peer_device).count() == 0


def test_an_empty_pool_yields_a_bundle_without_an_otpk(
    api, active_user, device, auth_headers, peer, peer_device
):
    """The otpk field is absent when the pool is empty: the client handles that per
    protocol, and the server neither errors nor fabricates a key."""
    response = api.post(
        claim_url(peer.id), {}, format="json", **auth_headers(active_user, device)
    )

    assert response.status_code == 200
    bundle = response.json()["bundles"][0]
    assert "otpk" not in bundle
    assert bundle["ik_pub"]  # the rest of the bundle is still served


def test_each_claim_takes_a_different_prekey(
    api, active_user, device, auth_headers, peer, peer_device
):
    stock_prekeys(peer_device, 3)
    headers = auth_headers(active_user, device)

    seen = [
        api.post(claim_url(peer.id), {}, format="json", **headers).json()["bundles"][0][
            "otpk"
        ]["key_id"]
        for _ in range(3)
    ]

    assert sorted(seen) == [0, 1, 2]
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 0


def test_device_ids_narrows_the_claim(
    api, active_user, device, auth_headers, peer, peer_device
):
    other = make_device(peer, registration_id=556)

    response = api.post(
        claim_url(peer.id),
        {"device_ids": [str(other.id)]},
        format="json",
        **auth_headers(active_user, device),
    )

    returned = {b["device_id"] for b in response.json()["bundles"]}
    assert returned == {str(other.id)}


def test_an_explicit_empty_device_id_list_claims_nothing(
    api, active_user, device, auth_headers, peer, peer_device
):
    """Treating `[]` as "all" would silently burn a one-time prekey on every device."""
    stock_prekeys(peer_device, 1)

    response = api.post(
        claim_url(peer.id),
        {"device_ids": []},
        format="json",
        **auth_headers(active_user, device),
    )

    assert response.json()["bundles"] == []
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 1


def test_a_malformed_device_id_is_a_400_not_a_500(
    api, active_user, device, auth_headers, peer, peer_device
):
    """An unparsed value reaching a uuid column raises Django's ValidationError, which
    DRF does not handle."""
    response = api.post(
        claim_url(peer.id),
        {"device_ids": ["not-a-uuid"]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert response.status_code == 400


def test_a_json_array_body_is_a_400_not_a_500(
    api, active_user, device, auth_headers, peer
):
    response = api.post(
        claim_url(peer.id), ["nope"], format="json", **auth_headers(active_user, device)
    )

    assert response.status_code == 400


def test_revoked_devices_are_not_claimable(
    api, active_user, device, auth_headers, peer, peer_device
):
    stock_prekeys(peer_device, 1)
    peer_device.revoked_date = timezone.now().date()
    peer_device.save(update_fields=["revoked_date"])

    response = api.post(
        claim_url(peer.id), {}, format="json", **auth_headers(active_user, device)
    )

    assert response.json()["bundles"] == []
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 1


def test_a_deactivated_users_devices_are_not_claimable(
    api, active_user, device, auth_headers, peer, peer_device
):
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    response = api.post(
        claim_url(peer.id), {}, format="json", **auth_headers(active_user, device)
    )

    assert response.json()["bundles"] == []


def test_key_packages_are_handed_out_once_each(
    api, active_user, device, auth_headers, peer, peer_device
):
    stock_keypackages(peer_device, 2)
    headers = auth_headers(active_user, device)

    first = api.post(kp_claim_url(peer.id), {}, format="json", **headers)
    second = api.post(kp_claim_url(peer.id), {}, format="json", **headers)
    third = api.post(kp_claim_url(peer.id), {}, format="json", **headers)

    assert len(first.json()["keypackages"]) == 1
    assert len(second.json()["keypackages"]) == 1
    assert third.json()["keypackages"] == []  # exhausted, not an error
    assert KeyPackage.objects.filter(device=peer_device).count() == 0


def test_claiming_a_users_own_devices_is_normal(api, active_user, device, auth_headers):
    """Self-sync: a user claims their own other devices to start a session."""
    mine = make_device(active_user, registration_id=77)
    stock_prekeys(mine, 1)

    response = api.post(
        claim_url(active_user.id),
        {"device_ids": [str(mine.id)]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert response.json()["bundles"][0]["device_id"] == str(mine.id)


def test_an_anonymous_claim_is_rejected(api, peer, peer_device):
    assert api.post(claim_url(peer.id), {}, format="json").status_code == 401
