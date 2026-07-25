"""Cross-signing identity and device-signature relay.

Server-side halves only. The security property — a peer refusing to encrypt to an
unsigned device, or alarming on a changed master key — lives in the client and is
specified in CLIENT_CONTRACT.md; these tests prove the server relays the material
verbatim and never fakes, fills in, or smooths over any of it.
"""
import base64

import pytest

from devices.models import Device, UserIdentity

from .conftest import DEVICES_URL, make_device, register_payload

pytestmark = pytest.mark.django_db

IDENTITY_URL = "/api/v1/me/identity"


def peer_identity_url(user_id):
    return f"/api/v1/users/{user_id}/identity"


def peer_devices_url(user_id):
    return f"/api/v1/users/{user_id}/devices"


def claim_url(user_id):
    return f"/api/v1/users/{user_id}/keys/claim"


def b64key(seed=b"k"):
    return base64.b64encode((seed * 32)[:32]).decode()


def b64sig(seed=b"g"):
    return base64.b64encode((seed * 64)[:64]).decode()


def identity_payload(version=1, master=b"m", self_signing=b"s", user_signing=b"u",
                     sig=b"g", **overrides):
    payload = {
        "master_pub": b64key(master),
        "self_signing_pub": b64key(self_signing),
        "user_signing_pub": b64key(user_signing),
        "master_sig": b64sig(sig),
        "version": version,
    }
    payload.update(overrides)
    return payload


def test_a_published_identity_reads_back_byte_identical(api, active_user, device,
                                                        auth_headers, peer,
                                                        peer_device):
    payload = identity_payload()
    headers = auth_headers(active_user, device)

    assert api.put(IDENTITY_URL, payload, format="json", **headers).status_code == 200

    body = api.get(peer_identity_url(active_user.id),
                   **auth_headers(peer, peer_device)).json()
    assert body == payload


def test_a_stale_or_equal_version_is_rejected_without_mutating_stored_bytes(
        api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    api.put(IDENTITY_URL, identity_payload(version=2), format="json", **headers)

    for version in (2, 1):
        response = api.put(IDENTITY_URL,
                           identity_payload(version=version, master=b"X"),
                           format="json", **headers)
        assert response.status_code == 409
        assert response.json()["code"] == "stale_version"

    identity = UserIdentity.objects.get(user=active_user)
    assert bytes(identity.master_pub) == b"m" * 32
    assert identity.version == 2


def test_an_unpublished_identity_is_a_404(api, active_user, device, auth_headers, peer):
    response = api.get(peer_identity_url(peer.id),
                       **auth_headers(active_user, device))

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


def test_a_deactivated_users_identity_is_a_404(api, active_user, device, auth_headers,
                                               peer, peer_device):
    api.put(IDENTITY_URL, identity_payload(), format="json",
            **auth_headers(peer, peer_device))
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    assert api.get(peer_identity_url(peer.id),
                   **auth_headers(active_user, device)).status_code == 404


@pytest.mark.parametrize("field, value", [
    ("master_pub", "not-base64!!"),
    ("master_sig", ""),
    ("master_sig", "AAAA"),          # decodes to 3 bytes, not 64
    ("version", -1),
    ("version", 2 ** 40),
])
def test_malformed_identity_material_is_rejected(api, active_user, device,
                                                 auth_headers, field, value):
    response = api.put(IDENTITY_URL, identity_payload(**{field: value}),
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 400


def test_unknown_identity_fields_are_rejected(api, active_user, device, auth_headers):
    response = api.put(IDENTITY_URL, identity_payload(recovery_key="oops"),
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 400


def test_the_peer_list_and_claim_surface_the_cross_sig_verbatim(
        api, active_user, device, auth_headers, peer):
    signed = make_device(peer, registration_id=700, cross_sig=b"\xc5" * 64,
                         bundle_version=3)
    headers = auth_headers(active_user, device)
    expected = base64.b64encode(b"\xc5" * 64).decode()

    listed = api.get(peer_devices_url(peer.id), **headers).json()["devices"][0]
    claimed = api.post(claim_url(peer.id), {}, format="json",
                       **headers).json()["bundles"][0]

    for entry in (listed, claimed):
        assert entry["device_id"] == str(signed.id)
        assert entry["cross_sig"] == expected
        assert entry["bundle_version"] == 3


def test_an_unsigned_device_stays_visibly_unsigned_everywhere(api, active_user, device,
                                                              auth_headers, peer,
                                                              peer_device):
    """Server-side half of "forged enrollment rejected": a device with no cross_sig
    (registration now requires one, so only a device from before the tightening
    can be unsigned — created here directly, as the migration left them) must
    appear with cross_sig null in the list and the claim, and the DB column must
    be null — no code path may substitute, default, or synthesize a signature.
    The other half — a peer refusing to encrypt to an unsigned device — is client
    behaviour, belongs to CLIENT_CONTRACT.md, and is deliberately not simulated
    here."""
    legacy = make_device(peer, registration_id=701)  # pre-cross-signing row
    headers = auth_headers(active_user, device)

    listed = api.get(peer_devices_url(peer.id), **headers).json()["devices"]
    claimed = api.post(claim_url(peer.id), {}, format="json",
                       **headers).json()["bundles"]

    by_id = {entry["device_id"]: entry for entry in listed}
    assert by_id[str(legacy.id)]["cross_sig"] is None
    assert by_id[str(legacy.id)]["bundle_version"] == 0
    by_id = {entry["device_id"]: entry for entry in claimed}
    assert by_id[str(legacy.id)]["cross_sig"] is None
    legacy.refresh_from_db()
    assert legacy.cross_sig is None


def test_a_substituted_master_key_is_served_verbatim_not_smoothed_over(
        api, active_user, device, auth_headers, peer, peer_device):
    """Server-side half of "substituted master key alarms": overwriting an identity
    with a different master_pub at a higher version must be returned exactly as
    stored, version incremented — the server does not merge, hide, or reconcile the
    change. The alarm itself (blocking the conversation pending re-verification) is
    client behaviour, specified in CLIENT_CONTRACT.md."""
    mine = auth_headers(active_user, device)
    api.put(IDENTITY_URL, identity_payload(version=1, master=b"A"), format="json",
            **mine)

    replaced = identity_payload(version=2, master=b"B", sig=b"h")
    assert api.put(IDENTITY_URL, replaced, format="json", **mine).status_code == 200

    body = api.get(peer_identity_url(active_user.id),
                   **auth_headers(peer, peer_device)).json()
    assert body == replaced
    assert body["version"] == 2


def test_registration_stores_the_cross_sig_and_bundle_version(api, active_user, device,
                                                              auth_headers):
    from .conftest import publish_identity
    publish_identity(active_user)
    payload = register_payload(cross_sig=b64sig(b"r"), bundle_version=5)

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    stored = Device.objects.get(id=response.json()["device_id"])
    assert bytes(stored.cross_sig) == b"r" * 64
    assert stored.bundle_version == 5


def test_a_prekey_replenish_can_refresh_the_cross_signature(api, active_user, device,
                                                            auth_headers):
    from .conftest import pubkey
    body = {"spk": {"spk_id": 9, "pub": pubkey(b"n"), "sig": pubkey(b"o")},
            "cross_sig": b64sig(b"f"), "bundle_version": 2}

    response = api.put(f"{DEVICES_URL}/{device.id}/prekeys", body, format="json",
                       **auth_headers(active_user, device))

    assert response.status_code == 200
    device.refresh_from_db()
    assert device.spk_id == 9
    assert bytes(device.cross_sig) == b"f" * 64
    assert device.bundle_version == 2


def test_a_malformed_cross_sig_at_registration_is_rejected(api, active_user, device,
                                                           auth_headers):
    response = api.post(DEVICES_URL, register_payload(cross_sig="AAAA"),
                        format="json", **auth_headers(active_user, device))

    assert response.status_code == 400
