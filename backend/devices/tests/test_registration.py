"""`POST /me/devices` — registration, the device cap, and input that must not 500 (§A5)."""
import pytest
from django.urls import reverse

from accounts.tokens import issue_register_scope
from devices.models import Device, KeyPackage, OneTimePrekey

from .conftest import (DEVICES_URL, keypackage_blob, label_blob, make_device, pubkey,
                       register_payload)

pytestmark = pytest.mark.django_db


def bearer(access):
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


def test_a_register_scope_token_registers_a_device_and_gets_full_tokens(api, active_user):
    """The register-scope token from login exists only to reach this endpoint (§A8)."""
    response = api.post(DEVICES_URL, register_payload(otpks=3, keypackages=2),
                        format="json", **bearer(issue_register_scope(active_user)))

    assert response.status_code == 201
    body = response.json()
    assert body["scope"] == "full"
    assert body["access"] and body["refresh"]
    device = Device.objects.get(id=body["device_id"])
    assert device.user_id == active_user.id
    assert OneTimePrekey.objects.filter(device=device).count() == 3
    assert KeyPackage.objects.filter(device=device).count() == 2
    # The issued token is genuinely full scope: it reaches an endpoint the register
    # token could not.
    assert api.get(reverse("user-directory"), **bearer(body["access"])).status_code == 200


def test_a_full_scope_token_may_also_register_another_device(api, active_user, device,
                                                             auth_headers):
    response = api.post(DEVICES_URL, register_payload(), format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 201
    assert Device.objects.filter(user=active_user).count() == 2


def test_the_label_blob_is_stored_when_supplied(api, active_user, auth_headers, device):
    response = api.post(DEVICES_URL, register_payload(label_blob=label_blob()),
                        format="json", **auth_headers(active_user, device))

    stored = Device.objects.get(id=response.json()["device_id"]).label_blob
    assert stored is not None


def test_the_eleventh_live_device_is_refused(api, active_user, auth_headers, settings):
    for i in range(settings.MAX_DEVICES_PER_USER):
        make_device(active_user, registration_id=100 + i)
    first = Device.objects.filter(user=active_user).first()

    response = api.post(DEVICES_URL, register_payload(), format="json",
                        **auth_headers(active_user, first))

    assert response.status_code == 409
    assert response.json()["code"] == "device_limit"
    assert Device.objects.filter(user=active_user).count() == settings.MAX_DEVICES_PER_USER


def test_revoked_devices_do_not_count_against_the_cap(api, active_user, auth_headers,
                                                      settings):
    from django.utils import timezone
    live = make_device(active_user, registration_id=1)
    for i in range(settings.MAX_DEVICES_PER_USER + 4):
        make_device(active_user, registration_id=200 + i,
                    revoked_date=timezone.now().date())

    response = api.post(DEVICES_URL, register_payload(), format="json",
                        **auth_headers(active_user, live))

    assert response.status_code == 201


def test_a_duplicate_key_id_in_the_payload_is_a_400_not_a_500(api, active_user, device,
                                                              auth_headers):
    """`unique (device, key_id)` turns a repeated key_id into an IntegrityError from
    bulk_create unless the serializer rejects it first."""
    payload = register_payload(otpks=0)
    payload["otpks"] = [{"key_id": 7, "pub": pubkey(b"a")},
                        {"key_id": 7, "pub": pubkey(b"b")}]

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400
    assert Device.objects.filter(user=active_user).count() == 1  # nothing committed


def test_an_out_of_range_key_id_is_a_400_not_a_500(api, active_user, device,
                                                   auth_headers):
    """PositiveIntegerField is a 32-bit column; a larger value reaches it as a DataError."""
    payload = register_payload(otpks=0)
    payload["otpks"] = [{"key_id": 2 ** 40, "pub": pubkey()}]

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


@pytest.mark.parametrize("field, value", [
    ("ik_pub", "not-base64!!"),
    ("spk_pub", ""),
    ("ik_pub", pubkey()[:8]),      # decodes, but far under PUBKEY_MIN
    ("registration_id", -1),
    ("spk_id", 2 ** 40),
])
def test_malformed_key_material_is_rejected(api, active_user, device, auth_headers,
                                            field, value):
    response = api.post(DEVICES_URL, register_payload(**{field: value}), format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


def test_a_label_blob_outside_its_bucket_is_rejected_without_echoing_it(
        api, active_user, device, auth_headers):
    import base64
    off_bucket = base64.b64encode(b"x" * 300).decode()

    response = api.post(DEVICES_URL, register_payload(label_blob=off_bucket),
                        format="json", **auth_headers(active_user, device))

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"
    assert off_bucket not in response.content.decode()


def test_a_keypackage_outside_its_bucket_is_rejected(api, active_user, device,
                                                     auth_headers):
    import base64
    payload = register_payload()
    payload["keypackages"] = [base64.b64encode(b"x" * 999).decode()]

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"


def test_unknown_fields_are_rejected(api, active_user, device, auth_headers):
    """§A5: "Unknown fields rejected"."""
    response = api.post(DEVICES_URL, register_payload(private_key="oops"),
                        format="json", **auth_headers(active_user, device))

    assert response.status_code == 400


def test_more_than_two_hundred_otpks_are_rejected(api, active_user, device, auth_headers):
    response = api.post(DEVICES_URL, register_payload(otpks=201), format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


def test_more_than_a_hundred_keypackages_are_rejected(api, active_user, device,
                                                      auth_headers):
    payload = register_payload()
    payload["keypackages"] = [keypackage_blob() for _ in range(101)]

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


def test_an_anonymous_registration_is_rejected(api):
    assert api.post(DEVICES_URL, register_payload(), format="json").status_code == 401
