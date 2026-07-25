"""Hybrid post-quantum prekey storage and claim.

Server-side halves only: the server stores and serves ML-KEM-768 material as
opaque bytes. The hybrid guarantee itself — refusing or flagging a session when a
bundle carries no PQ material — is client behaviour and lives in
CLIENT_CONTRACT.md; the adversarial test here proves the server never fakes that
material into existence.
"""
import base64
import threading

import pytest
from django.core.cache import cache
from django.db import connections
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full
from devices.models import Device, PqOneTimePrekey
from devices.serializers import PQ_PUBKEY_LEN
from devices.views import MAX_STORED_PQ_OTPKS

from .conftest import (DEVICES_URL, PASSWORD, make_device, pq_pubkey,
                       publish_identity, pubkey, register_payload,
                       stock_pq_prekeys)

pytestmark = pytest.mark.django_db

CONCURRENT_CLAIMS = 12


def claim_url(user_id):
    return f"/api/v1/users/{user_id}/keys/claim"


def b64sig(seed=b"g"):
    return base64.b64encode((seed * 64)[:64]).decode()


def pq_spk(seed=b"P", spk_id=41):
    return {"spk_id": spk_id, "pub": pq_pubkey(seed), "sig": b64sig(seed)}


def test_pq_material_round_trips_byte_identically(api, active_user, device,
                                                  auth_headers, peer, peer_device):
    publish_identity(peer)
    payload = register_payload(
        pq_spk=pq_spk(b"E"),
        pq_otpks=[{"key_id": 7, "pub": pq_pubkey(b"O")}])
    registered = api.post(DEVICES_URL, payload, format="json",
                          **auth_headers(peer, peer_device)).json()

    bundles = api.post(claim_url(peer.id),
                       {"device_ids": [registered["device_id"]]}, format="json",
                       **auth_headers(active_user, device)).json()["bundles"]

    bundle = bundles[0]
    assert bundle["pq_spk_id"] == 41
    assert bundle["pq_spk_pub"] == pq_pubkey(b"E")
    assert bundle["pq_spk_sig"] == b64sig(b"E")
    assert bundle["pq_otpk"] == {"key_id": 7, "pub": pq_pubkey(b"O")}


def test_a_claimed_pq_otpk_is_deleted_and_never_reserved(api, active_user, device,
                                                         auth_headers, peer,
                                                         peer_device):
    peer_device.pq_spk_id = 1
    peer_device.pq_spk_pub = b"E" * PQ_PUBKEY_LEN
    peer_device.pq_spk_sig = b"s" * 64
    peer_device.save()
    stock_pq_prekeys(peer_device, 1, start=30)
    headers = auth_headers(active_user, device)

    first = api.post(claim_url(peer.id), {}, format="json", **headers).json()
    second = api.post(claim_url(peer.id), {}, format="json", **headers).json()

    assert first["bundles"][0]["pq_otpk"]["key_id"] == 30
    assert "pq_otpk" not in second["bundles"][0]
    assert second["bundles"][0]["pq_spk_id"] == 1  # signed prekey still served
    assert PqOneTimePrekey.objects.filter(device=peer_device).count() == 0


@pytest.mark.parametrize("nbytes", [PQ_PUBKEY_LEN - 1, PQ_PUBKEY_LEN + 1, 32, 0])
def test_a_wrong_length_pq_key_is_a_400_not_a_500(api, active_user, device,
                                                  auth_headers, nbytes):
    bad = base64.b64encode(b"x" * nbytes).decode()
    payload = register_payload(pq_otpks=[{"key_id": 1, "pub": bad}])

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


def test_a_wrong_length_pq_spk_is_a_400_not_a_500(api, active_user, device,
                                                  auth_headers):
    payload = register_payload(pq_spk={"spk_id": 1, "pub": pubkey(), "sig": b64sig()})

    response = api.post(DEVICES_URL, payload, format="json",
                        **auth_headers(active_user, device))

    assert response.status_code == 400


def test_exceeding_the_pq_cap_is_a_409_and_rotates_nothing(api, active_user, device,
                                                           auth_headers):
    """The ordering hazard the replenish comment describes: the cap check must run
    before the signed-prekey write, or a device told "409, nothing stored" would
    have had its PQ signed prekey rotated anyway."""
    stock_pq_prekeys(device, MAX_STORED_PQ_OTPKS)
    body = {"pq_spk": pq_spk(b"N", spk_id=99),
            "pq_otpks": [{"key_id": 5000, "pub": pq_pubkey(b"z")}]}

    response = api.put(f"{DEVICES_URL}/{device.id}/prekeys", body, format="json",
                       **auth_headers(active_user, device))

    assert response.status_code == 409
    assert response.json()["code"] == "prekey_limit"
    device.refresh_from_db()
    assert device.pq_spk_id is None  # the 409 stored and rotated nothing
    assert PqOneTimePrekey.objects.filter(device=device).count() == \
        MAX_STORED_PQ_OTPKS


def test_replenish_stores_pq_material_and_the_count_endpoint_reports_it(
        api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    body = {"pq_spk": pq_spk(b"R", spk_id=8),
            "pq_otpks": [{"key_id": i, "pub": pq_pubkey(bytes([65 + i]))}
                         for i in range(3)]}

    assert api.put(f"{DEVICES_URL}/{device.id}/prekeys", body, format="json",
                   **headers).status_code == 200

    device.refresh_from_db()
    assert device.pq_spk_id == 8
    assert bytes(device.pq_spk_pub) == (b"R" * PQ_PUBKEY_LEN)[:PQ_PUBKEY_LEN]
    counts = api.get(f"{DEVICES_URL}/{device.id}/prekeys/count", **headers).json()
    assert counts["pq_otpk_count"] == 3


def test_a_classical_only_bundle_omits_the_pq_fields_entirely(api, active_user,
                                                              device, auth_headers,
                                                              peer, peer_device):
    """Server-side half of "PQ hybrid downgrade blocked": a device with no PQ
    material yields a bundle with the PQ fields absent — not null, not empty, not
    zero-filled — so a classical-only bundle is visibly classical-only. There is no
    code path that substitutes classical material into a PQ field. The other half —
    the client refusing or flagging a classical-only session — is client behaviour
    and belongs to CLIENT_CONTRACT.md, deliberately not simulated here."""
    stock_pq_prekeys(peer_device, 1)  # orphaned PQ OTPKs without a pq_spk

    bundle = api.post(claim_url(peer.id), {}, format="json",
                      **auth_headers(active_user, device)).json()["bundles"][0]

    assert "pq_spk_id" not in bundle
    assert "pq_spk_pub" not in bundle
    assert "pq_spk_sig" not in bundle
    assert "pq_otpk" not in bundle
    # And the orphaned one-time key was not burned for a classical-only bundle.
    assert PqOneTimePrekey.objects.filter(device=peer_device).count() == 1


class PqClaimRaceTests(TransactionTestCase):
    """Mirror of test_claim_race.py for the PQ pool: real committed transactions
    racing over `SELECT ... FOR UPDATE SKIP LOCKED` + delete."""

    def setUp(self):
        cache.clear()
        self.claimant = User.objects.create_user(username="claimant",
                                                 password=PASSWORD, is_active=True)
        self.claimant_device = make_device(self.claimant, registration_id=1)
        self.owner = User.objects.create_user(username="owner", password=PASSWORD,
                                              is_active=True)
        self.owner_device = make_device(
            self.owner, registration_id=2, pq_spk_id=1,
            pq_spk_pub=b"E" * PQ_PUBKEY_LEN, pq_spk_sig=b"s" * 64)
        access, _refresh = issue_full(self.claimant, self.claimant_device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def test_one_pq_prekey_is_handed_to_at_most_one_concurrent_claimant(self):
        stock_pq_prekeys(self.owner_device, 1, start=77)
        start = threading.Barrier(CONCURRENT_CLAIMS)
        received, failures = [], []
        lock = threading.Lock()

        def claim():
            try:
                start.wait(timeout=10)
                response = APIClient().post(
                    f"/api/v1/users/{self.owner.id}/keys/claim", {},
                    format="json", **self.headers)
                if response.status_code != 200:
                    with lock:
                        failures.append(response.status_code)
                    return
                bundle = response.json()["bundles"][0]
                if "pq_otpk" in bundle:
                    with lock:
                        received.append(bundle["pq_otpk"]["key_id"])
            except Exception as exc:  # noqa: BLE001 - surfaced through `failures`
                with lock:
                    failures.append(repr(exc))
            finally:
                connections.close_all()

        threads = [threading.Thread(target=claim) for _ in range(CONCURRENT_CLAIMS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(failures, [])
        self.assertEqual(received, [77],
                         f"the single PQ OTPK went to {len(received)} claimants")
        self.assertEqual(
            PqOneTimePrekey.objects.filter(device=self.owner_device).count(), 0)
