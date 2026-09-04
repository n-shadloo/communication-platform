import base64

import pytest

from devices.models import Device, OneTimePrekey

from .conftest import (
    DEVICES_URL,
    cross_sig_b64,
    label_blob,
    make_device,
    pubkey,
    publish_identity,
    register_payload,
)

pytestmark = pytest.mark.django_db(transaction=True)


def test_a_register_scope_token_registers_a_device_and_gets_full_tokens(
    http, active_user, register_bearer
):
    """The register-scope token from login exists only to reach this endpoint."""
    response = http.post(
        DEVICES_URL, json=register_payload(otpks=3), headers=register_bearer(active_user)
    )

    assert response.status_code == 201
    body = response.json()
    assert body["scope"] == "full"
    assert body["access"] and body["refresh"]
    device = Device.objects.get(id=body["device_id"])
    assert device.user_id == active_user.id
    assert OneTimePrekey.objects.filter(device=device).count() == 3
    # The issued token is genuinely full scope: it reaches an endpoint the register
    # token could not.
    assert (
        http.get(
            DEVICES_URL, headers={"Authorization": f"Bearer {body['access']}"}
        ).status_code
        == 200
    )


def test_a_full_scope_token_may_also_register_another_device(
    http, active_user, device, bearer
):
    publish_identity(active_user)
    response = http.post(
        DEVICES_URL, json=register_payload(), headers=bearer(active_user, device)
    )

    assert response.status_code == 201
    assert Device.objects.filter(user=active_user).count() == 2


def test_the_label_blob_is_stored_when_supplied(http, active_user, bearer, device):
    publish_identity(active_user)
    response = http.post(
        DEVICES_URL,
        json=register_payload(label_blob=label_blob()),
        headers=bearer(active_user, device),
    )

    stored = Device.objects.get(id=response.json()["device_id"]).label_blob
    assert stored is not None


def test_the_eleventh_live_device_is_refused(http, active_user, bearer, settings):
    for i in range(settings.MAX_DEVICES_PER_USER):
        make_device(active_user, registration_id=100 + i)
    first = Device.objects.filter(user=active_user).first()

    response = http.post(
        DEVICES_URL, json=register_payload(), headers=bearer(active_user, first)
    )

    assert response.status_code == 409
    assert response.json()["code"] == "device_limit"
    assert (
        Device.objects.filter(user=active_user).count() == settings.MAX_DEVICES_PER_USER
    )


def test_revoked_devices_do_not_count_against_the_cap(
    http, active_user, bearer, settings
):
    from django.utils import timezone

    publish_identity(active_user)
    live = make_device(active_user, registration_id=1)
    for i in range(settings.MAX_DEVICES_PER_USER + 4):
        make_device(
            active_user, registration_id=200 + i, revoked_date=timezone.now().date()
        )

    response = http.post(
        DEVICES_URL, json=register_payload(), headers=bearer(active_user, live)
    )

    assert response.status_code == 201


def test_a_duplicate_key_id_in_the_payload_is_a_400_not_a_500(
    http, active_user, device, bearer
):
    """`unique (device, key_id)` turns a repeated key_id into an IntegrityError from
    bulk_create unless the schema rejects it first."""
    payload = register_payload(otpks=0)
    payload["otpks"] = [
        {"key_id": 7, "pub": pubkey(b"a")},
        {"key_id": 7, "pub": pubkey(b"b")},
    ]

    response = http.post(DEVICES_URL, json=payload, headers=bearer(active_user, device))

    assert response.status_code == 400
    assert Device.objects.filter(user=active_user).count() == 1  # nothing committed


def test_an_out_of_range_key_id_is_a_400_not_a_500(http, active_user, device, bearer):
    """PositiveIntegerField is a 32-bit column; a larger value reaches it as a
    DataError."""
    payload = register_payload(otpks=0)
    payload["otpks"] = [{"key_id": 2**40, "pub": pubkey()}]

    response = http.post(DEVICES_URL, json=payload, headers=bearer(active_user, device))

    assert response.status_code == 400


@pytest.mark.parametrize(
    "field, value",
    [
        ("ik_pub", "not-base64!!"),
        ("spk_pub", ""),
        ("ik_pub", pubkey()[:8]),  # decodes, but far under PUBKEY_MIN
        ("registration_id", -1),
        ("spk_id", 2**40),
    ],
)
def test_malformed_key_material_is_rejected(
    http, active_user, device, bearer, field, value
):
    response = http.post(
        DEVICES_URL,
        json=register_payload(**{field: value}),
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400


def test_a_malformed_key_names_the_field_it_failed_on(http, active_user, device, bearer):
    """The decode runs inside its own field, so the path a client reads points at
    the item that failed rather than at the whole body."""
    payload = register_payload(otpks=0)
    payload["otpks"] = [
        {"key_id": 1, "pub": pubkey()},
        {"key_id": 2, "pub": "not-base64!!"},
    ]

    response = http.post(DEVICES_URL, json=payload, headers=bearer(active_user, device))

    body = response.json()
    assert body["code"] == "invalid_request"
    assert body["detail"] == {"otpks.1.pub": ["invalid base64"]}


def test_a_label_blob_outside_its_bucket_is_rejected_without_echoing_it(
    http, active_user, device, bearer
):
    off_bucket = base64.b64encode(b"x" * 300).decode()

    response = http.post(
        DEVICES_URL,
        json=register_payload(label_blob=off_bucket),
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"
    assert off_bucket not in response.text


def test_unknown_fields_are_rejected(http, active_user, device, bearer):
    response = http.post(
        DEVICES_URL,
        json=register_payload(private_key="oops"),
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400


def test_more_than_two_hundred_otpks_are_rejected(http, active_user, device, bearer):
    response = http.post(
        DEVICES_URL,
        json=register_payload(otpks=201),
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400


def test_an_anonymous_registration_is_rejected(http):
    assert http.post(DEVICES_URL, json=register_payload()).status_code == 401


def test_registration_leaves_the_device_never_cross_signed(
    http, active_user, register_bearer
):
    """The enrollment order the client can actually execute: the signed bundle
    covers `device_id`, which this request mints, so no first call can carry a
    valid cross_sig. The row is therefore born in the null/0 "never cross-signed"
    state peers already refuse, and nothing substitutes or synthesizes a value."""
    response = http.post(
        DEVICES_URL, json=register_payload(), headers=register_bearer(active_user)
    )

    assert response.status_code == 201
    stored = Device.objects.get(id=response.json()["device_id"])
    assert stored.cross_sig is None
    assert stored.bundle_version == 0


@pytest.mark.parametrize(
    "extra",
    [
        {"cross_sig": cross_sig_b64()},
        {"bundle_version": 1},
        # The payload a client written against the old contract sends: both must be
        # named in the error, not just the first one found.
        {"cross_sig": cross_sig_b64(), "bundle_version": 1},
    ],
)
def test_registration_refuses_the_cross_signing_fields_with_a_pointer(
    http, active_user, register_bearer, extra
):
    """No valid value exists for either field here, so the endpoint refuses both
    rather than storing bytes that can only be wrong — and the error names the
    endpoint that does accept them, since "Extra inputs are not permitted" on a
    field that was mandatory until recently reads like a version mismatch.

    Not a security control: peers must reject unverifiable devices on their own,
    and a modified server would accept anything. It stops a client from believing
    it cross-signed a device it did not."""
    payload = register_payload()
    payload.update(extra)

    response = http.post(DEVICES_URL, json=payload, headers=register_bearer(active_user))

    assert response.status_code == 400
    detail = response.json()["detail"]
    for field in extra:
        assert "prekeys" in str(detail[field]), (
            f"{field} not pointed at the right endpoint"
        )
    assert Device.objects.filter(user=active_user).count() == 0


def test_a_second_device_requires_a_published_identity(http, active_user, device, bearer):
    """Same completeness-check framing: past the first device, an account with no
    published identity registering another device can only be a mis-sequenced
    client, so it is told so instead of producing an unverifiable device."""
    response = http.post(
        DEVICES_URL, json=register_payload(), headers=bearer(active_user, device)
    )

    assert response.status_code == 400
    assert response.json()["code"] == "identity_required"
    assert Device.objects.filter(user=active_user).count() == 1


def test_the_first_device_is_exempt_from_the_identity_precondition(
    http, active_user, register_bearer
):
    """The bootstrap exemption: a fresh account's register-scope token reaches
    only this endpoint, so it cannot have published an identity yet. The client
    publishes immediately after with the full token issued here."""
    response = http.post(
        DEVICES_URL, json=register_payload(), headers=register_bearer(active_user)
    )

    assert response.status_code == 201
