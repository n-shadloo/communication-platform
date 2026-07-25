"""The revocation cascade.

One removal must cut the device off completely: its tokens, its mailbox, its
published key material, its presence in peers' device lists, and the ETag siblings
poll.
"""
import pytest
from django.urls import reverse

from accounts.tokens import issue_full
from core.buckets import ENVELOPE_BUCKETS
from devices.models import Device, KeyPackage, OneTimePrekey, PqOneTimePrekey
from messaging.models import QueuedEnvelope

from .conftest import (DEVICES_URL, make_device, stock_keypackages,
                       stock_pq_prekeys, stock_prekeys)

pytestmark = pytest.mark.django_db


def bearer(access):
    return {"HTTP_AUTHORIZATION": f"Bearer {access}"}


@pytest.fixture
def doomed(active_user):
    """A fully-provisioned second device, about to be revoked."""
    device = make_device(active_user, registration_id=8080)
    stock_prekeys(device, 4)
    stock_pq_prekeys(device, 4)
    stock_keypackages(device, 3)
    KeyPackage.objects.create(device=device, blob=b"L" * 4096, is_last_resort=True)
    QueuedEnvelope.objects.bulk_create([
        QueuedEnvelope(recipient_device=device, seq=i + 1,
                       blob=b"c" * min(ENVELOPE_BUCKETS)) for i in range(5)])
    return device


def test_revocation_returns_204_and_marks_the_row(api, active_user, device,
                                                  auth_headers, doomed):
    response = api.delete(f"{DEVICES_URL}/{doomed.id}",
                          **auth_headers(active_user, device))

    assert response.status_code == 204
    doomed.refresh_from_db()
    assert doomed.revoked_date is not None


def test_the_revoked_devices_access_token_is_rejected(api, active_user, device,
                                                      auth_headers, doomed):
    """(a) `token_generation` is bumped, so DeviceJWTAuthentication refuses every
    outstanding access token for it."""
    access, _refresh = issue_full(active_user, doomed)
    assert api.get(reverse("user-directory"), **bearer(access)).status_code == 200

    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))

    response = api.get(reverse("user-directory"), **bearer(access))
    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_the_revoked_devices_refresh_token_fails(api, active_user, device,
                                                 auth_headers, doomed):
    """(b) Refresh re-checks the device, so it cannot mint a fresh pair."""
    _access, refresh = issue_full(active_user, doomed)

    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))

    response = api.post("/api/v1/auth/refresh", {"refresh": refresh}, format="json")
    assert response.status_code == 401
    assert response.json()["code"] == "token_revoked"


def test_the_queue_prekeys_and_keypackages_are_deleted(api, active_user, device,
                                                       auth_headers, doomed):
    """(c) Nothing of the device's data survives the revoke: classical and PQ
    one-time prekeys, every KeyPackage including the last-resort one, and the
    mailbox, all purged in the one revocation transaction (FS/PCS: no key
    material of a removed device may remain claimable)."""
    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))

    assert OneTimePrekey.objects.filter(device=doomed).count() == 0
    assert PqOneTimePrekey.objects.filter(device=doomed).count() == 0
    assert KeyPackage.objects.filter(device=doomed).count() == 0
    assert QueuedEnvelope.objects.filter(recipient_device=doomed).count() == 0


def test_a_revoked_devices_material_is_never_served_to_claimants(api, active_user,
                                                                 device, auth_headers,
                                                                 doomed, peer,
                                                                 peer_device):
    """The claim side of the same property: after the revoke, a claim against the
    account neither returns the revoked device nor hands out any of its one-time
    material (classical or PQ) or KeyPackages."""
    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))
    peer_headers = auth_headers(peer, peer_device)

    bundles = api.post(f"/api/v1/users/{active_user.id}/keys/claim", {},
                       format="json", **peer_headers).json()["bundles"]
    packages = api.post(f"/api/v1/users/{active_user.id}/keypackages/claim", {},
                        format="json", **peer_headers).json()["keypackages"]

    assert str(doomed.id) not in {b["device_id"] for b in bundles}
    assert str(doomed.id) not in {p["device_id"] for p in packages}


def test_the_revoked_device_leaves_the_peer_list(api, active_user, device,
                                                 auth_headers, doomed, peer,
                                                 peer_device):
    """(d) Peers stop seeing it, so they stop encrypting to it."""
    peer_headers = auth_headers(peer, peer_device)
    url = f"/api/v1/users/{active_user.id}/devices"
    assert str(doomed.id) in {d["device_id"]
                              for d in api.get(url, **peer_headers).json()["devices"]}

    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))

    assert str(doomed.id) not in {d["device_id"]
                                  for d in api.get(url, **peer_headers).json()["devices"]}


def test_the_device_list_etag_changes(api, active_user, device, auth_headers, doomed,
                                      peer, peer_device):
    """(e) Both the owner's siblings and peers notice on their next poll."""
    own_headers = auth_headers(active_user, device)
    peer_headers = auth_headers(peer, peer_device)
    peer_url = f"/api/v1/users/{active_user.id}/devices"
    own_before = api.get(DEVICES_URL, **own_headers)["ETag"]
    peer_before = api.get(peer_url, **peer_headers)["ETag"]

    api.delete(f"{DEVICES_URL}/{doomed.id}", **own_headers)

    assert api.get(DEVICES_URL, **own_headers)["ETag"] != own_before
    assert api.get(peer_url, **peer_headers)["ETag"] != peer_before


def test_a_sibling_device_is_untouched(api, active_user, device, auth_headers, doomed):
    """The cascade is scoped to one device, not the account."""
    stock_prekeys(device, 2, start=500)
    survivor_access, _ = issue_full(active_user, device)

    api.delete(f"{DEVICES_URL}/{doomed.id}", **auth_headers(active_user, device))

    assert api.get(reverse("user-directory"),
                   **bearer(survivor_access)).status_code == 200
    assert OneTimePrekey.objects.filter(device=device).count() == 2


def test_revoking_twice_is_a_404(api, active_user, device, auth_headers, doomed):
    headers = auth_headers(active_user, device)
    api.delete(f"{DEVICES_URL}/{doomed.id}", **headers)

    assert api.delete(f"{DEVICES_URL}/{doomed.id}", **headers).status_code == 404


def test_a_user_cannot_revoke_another_users_device(api, active_user, device,
                                                   auth_headers, peer, peer_device):
    response = api.delete(f"{DEVICES_URL}/{peer_device.id}",
                          **auth_headers(active_user, device))

    assert response.status_code == 404  # not 403: the device's existence is not confirmed
    peer_device.refresh_from_db()
    assert peer_device.revoked_date is None


def test_a_revoked_device_cannot_be_relabelled(api, active_user, device, auth_headers,
                                               doomed):
    from .conftest import label_blob
    headers = auth_headers(active_user, device)
    api.delete(f"{DEVICES_URL}/{doomed.id}", **headers)

    response = api.put(f"{DEVICES_URL}/{doomed.id}", {"label_blob": label_blob()},
                       format="json", **headers)

    assert response.status_code == 404


def test_relabelling_a_live_device_works(api, active_user, device, auth_headers):
    """Guards the guard above: the 404 is about revocation, not a broken PUT."""
    from .conftest import label_blob

    response = api.put(f"{DEVICES_URL}/{device.id}", {"label_blob": label_blob()},
                       format="json", **auth_headers(active_user, device))

    assert response.status_code == 200
    assert Device.objects.get(id=device.id).label_blob is not None
