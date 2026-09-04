"""Bundle contents and single consumption in the sequential case. The concurrent
case is test_claim_race.py."""

import base64

import pytest
from django.utils import timezone

from devices.models import OneTimePrekey

from .conftest import make_device, stock_prekeys

pytestmark = pytest.mark.django_db(transaction=True)


def claim_url(user_id):
    return f"/api/v1/users/{user_id}/keys/claim"


def test_a_bundle_carries_the_public_x3dh_material(
    http, active_user, device, bearer, peer, peer_device
):
    stock_prekeys(peer_device, 1, start=5)

    response = http.post(claim_url(peer.id), json={}, headers=bearer(active_user, device))

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
    http, active_user, device, bearer, peer, peer_device
):
    stock_prekeys(peer_device, 1)

    http.post(claim_url(peer.id), json={}, headers=bearer(active_user, device))

    assert OneTimePrekey.objects.filter(device=peer_device).count() == 0


def test_an_empty_pool_yields_a_bundle_without_an_otpk(
    http, active_user, device, bearer, peer, peer_device
):
    """The otpk field is absent when the pool is empty: the client handles that per
    protocol, and the server neither errors nor fabricates a key."""
    response = http.post(claim_url(peer.id), json={}, headers=bearer(active_user, device))

    assert response.status_code == 200
    bundle = response.json()["bundles"][0]
    assert "otpk" not in bundle
    assert bundle["ik_pub"]  # the rest of the bundle is still served


def test_a_multi_device_claim_consumes_exactly_the_keys_it_served(
    http, active_user, device, bearer, peer, peer_device
):
    """One claim is one transaction with one delete for the whole batch, so the
    delete has to name the rows by primary key. Naming them by the device set and
    the key-id set instead is a cross product, and it destroys a key that another
    device happened to number the same and that this call never handed out."""
    other = make_device(peer, registration_id=557)
    stock_prekeys(peer_device, 2, start=1)  # key ids 1, 2
    stock_prekeys(other, 2, start=2)  # key ids 2, 3

    bundles = http.post(
        claim_url(peer.id), json={}, headers=bearer(active_user, device)
    ).json()["bundles"]

    served = {b["device_id"]: b["otpk"]["key_id"] for b in bundles}
    assert served == {str(peer_device.id): 1, str(other.id): 2}
    left = {(str(row.device_id), row.key_id) for row in OneTimePrekey.objects.all()}
    assert left == {(str(peer_device.id), 2), (str(other.id), 3)}


def test_each_claim_takes_a_different_prekey(
    http, active_user, device, bearer, peer, peer_device
):
    stock_prekeys(peer_device, 3)
    headers = bearer(active_user, device)

    seen = [
        http.post(claim_url(peer.id), json={}, headers=headers).json()["bundles"][0][
            "otpk"
        ]["key_id"]
        for _ in range(3)
    ]

    assert sorted(seen) == [0, 1, 2]
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 0


def test_device_ids_narrows_the_claim(
    http, active_user, device, bearer, peer, peer_device
):
    other = make_device(peer, registration_id=556)

    response = http.post(
        claim_url(peer.id),
        json={"device_ids": [str(other.id)]},
        headers=bearer(active_user, device),
    )

    returned = {b["device_id"] for b in response.json()["bundles"]}
    assert returned == {str(other.id)}


def test_an_explicit_empty_device_id_list_claims_nothing(
    http, active_user, device, bearer, peer, peer_device
):
    """Treating `[]` as "all" would silently burn a one-time prekey on every device."""
    stock_prekeys(peer_device, 1)

    response = http.post(
        claim_url(peer.id),
        json={"device_ids": []},
        headers=bearer(active_user, device),
    )

    assert response.json()["bundles"] == []
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 1


def test_a_malformed_device_id_is_a_400_not_a_500(
    http, active_user, device, bearer, peer, peer_device
):
    """An unparsed value reaching a uuid column raises Django's ValidationError,
    which no handler below the route would turn into anything but a 500."""
    response = http.post(
        claim_url(peer.id),
        json={"device_ids": ["not-a-uuid"]},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400
    assert response.json()["code"] == "invalid_request"


def test_a_json_array_body_is_a_400_not_a_500(http, active_user, device, bearer, peer):
    response = http.post(
        claim_url(peer.id), json=["nope"], headers=bearer(active_user, device)
    )

    assert response.status_code == 400


def test_revoked_devices_are_not_claimable(
    http, active_user, device, bearer, peer, peer_device
):
    stock_prekeys(peer_device, 1)
    peer_device.revoked_date = timezone.now().date()
    peer_device.save(update_fields=["revoked_date"])

    response = http.post(claim_url(peer.id), json={}, headers=bearer(active_user, device))

    assert response.json()["bundles"] == []
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 1


def test_a_deactivated_users_devices_are_not_claimable(
    http, active_user, device, bearer, peer, peer_device
):
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    response = http.post(claim_url(peer.id), json={}, headers=bearer(active_user, device))

    assert response.json()["bundles"] == []


def test_claiming_a_users_own_devices_is_normal(http, active_user, device, bearer):
    """Self-sync: a user claims their own other devices to start a session."""
    mine = make_device(active_user, registration_id=77)
    stock_prekeys(mine, 1)

    response = http.post(
        claim_url(active_user.id),
        json={"device_ids": [str(mine.id)]},
        headers=bearer(active_user, device),
    )

    assert response.json()["bundles"][0]["device_id"] == str(mine.id)


def test_an_anonymous_claim_is_rejected(http, peer, peer_device):
    assert http.post(claim_url(peer.id), json={}).status_code == 401
