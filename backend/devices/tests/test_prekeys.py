import base64

import pytest

from devices.models import OneTimePrekey
from devices.schemas import MAX_STORED_OTPKS

from .conftest import DEVICES_URL, make_device, pubkey, stock_prekeys

pytestmark = pytest.mark.django_db(transaction=True)


def prekeys_url(device_id):
    return f"{DEVICES_URL}/{device_id}/prekeys"


def otpks(count, start=0):
    return [
        {"key_id": start + i, "pub": pubkey(bytes([65 + (i % 26)]))} for i in range(count)
    ]


def test_a_device_replenishes_its_own_prekeys(http, active_user, device, bearer):
    response = http.put(
        prekeys_url(device.id),
        json={"otpks": otpks(5)},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200
    assert response.json()["otpk_count"] == 5
    assert OneTimePrekey.objects.filter(device=device).count() == 5


def test_re_uploading_a_key_id_is_an_idempotent_retry(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    http.put(prekeys_url(device.id), json={"otpks": otpks(3)}, headers=headers)

    again = http.put(prekeys_url(device.id), json={"otpks": otpks(3)}, headers=headers)

    assert again.status_code == 200
    assert again.json()["otpk_count"] == 3


def test_a_duplicate_key_id_within_one_payload_is_a_400(
    http, active_user, device, bearer
):
    body = {
        "otpks": [{"key_id": 4, "pub": pubkey(b"a")}, {"key_id": 4, "pub": pubkey(b"b")}]
    }

    response = http.put(
        prekeys_url(device.id), json=body, headers=bearer(active_user, device)
    )

    assert response.status_code == 400


def test_the_signed_prekey_is_replaced_and_dated(http, active_user, device, bearer):
    """The server stores spk_pub/spk_sig and never verifies the signature; that is
    the client's job against ik_pub."""
    body = {"spk": {"spk_id": 77, "pub": pubkey(b"n"), "sig": pubkey(b"z")}}

    response = http.put(
        prekeys_url(device.id), json=body, headers=bearer(active_user, device)
    )

    assert response.status_code == 200
    device.refresh_from_db()
    assert device.spk_id == 77
    assert bytes(device.spk_pub) == base64.b64decode(pubkey(b"n"))
    assert bytes(device.spk_sig) == base64.b64decode(pubkey(b"z"))
    assert device.spk_updated_date is not None


def test_a_signed_prekey_missing_its_signature_is_rejected(
    http, active_user, device, bearer
):
    body = {"spk": {"spk_id": 1, "pub": pubkey()}}

    response = http.put(
        prekeys_url(device.id), json=body, headers=bearer(active_user, device)
    )

    assert response.status_code == 400


def test_replenishment_past_the_stored_cap_is_refused(http, active_user, device, bearer):
    """Without a stored cap, replenishment is an unbounded write primitive for any
    authenticated device."""
    stock_prekeys(device, MAX_STORED_OTPKS, start=1000)

    response = http.put(
        prekeys_url(device.id),
        json={"otpks": otpks(1)},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 409
    assert response.json()["code"] == "prekey_limit"
    assert OneTimePrekey.objects.filter(device=device).count() == MAX_STORED_OTPKS


def test_a_refused_replenishment_rotates_nothing(http, active_user, device, bearer):
    """The cap is checked before either write, so a device told "409, nothing
    stored" never finds its signed prekey rotated anyway."""
    stock_prekeys(device, MAX_STORED_OTPKS, start=1000)
    original_spk_id = device.spk_id
    body = {
        "spk": {"spk_id": 4242, "pub": pubkey(b"n"), "sig": pubkey(b"z")},
        "otpks": otpks(1),
    }

    response = http.put(
        prekeys_url(device.id), json=body, headers=bearer(active_user, device)
    )

    assert response.status_code == 409
    device.refresh_from_db()
    assert device.spk_id == original_spk_id


def test_the_count_endpoint_reports_the_pool(http, active_user, device, bearer):
    stock_prekeys(device, 12)

    response = http.get(
        f"{prekeys_url(device.id)}/count", headers=bearer(active_user, device)
    )

    assert response.json()["otpk_count"] == 12


@pytest.mark.parametrize(
    "method, suffix, body",
    [
        ("put", "", {"otpks": []}),
        ("get", "/count", None),
    ],
)
def test_a_device_cannot_touch_another_devices_prekeys(
    http, active_user, device, bearer, method, suffix, body
):
    """Token device_id must equal the path device, including a sibling device on the
    caller's own account."""
    sibling = make_device(active_user, registration_id=42)
    headers = bearer(active_user, device)
    url = f"{prekeys_url(sibling.id)}{suffix}"

    response = (
        getattr(http, method)(url, json=body, headers=headers)
        if body is not None
        else getattr(http, method)(url, headers=headers)
    )

    assert response.status_code == 403
    assert response.json()["code"] == "forbidden"


def test_a_device_cannot_touch_a_peers_prekeys(
    http, active_user, device, bearer, peer, peer_device
):
    response = http.put(
        prekeys_url(peer_device.id),
        json={"otpks": otpks(1)},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 403
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 0


def test_unknown_fields_are_rejected(http, active_user, device, bearer):
    response = http.put(
        prekeys_url(device.id),
        json={"otpks": [], "private": "no"},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400


def test_an_empty_body_is_a_no_op(http, active_user, device, bearer):
    response = http.put(
        prekeys_url(device.id), json={}, headers=bearer(active_user, device)
    )

    assert response.status_code == 200
    assert response.json()["otpk_count"] == 0
