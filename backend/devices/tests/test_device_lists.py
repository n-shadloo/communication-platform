import base64
import uuid

import pytest
from django.utils import timezone

from .conftest import (
    DEVICES_URL,
    label_blob,
    make_device,
    publish_identity,
    register_payload,
)

pytestmark = pytest.mark.django_db(transaction=True)


def peer_url(user_id):
    return f"/api/v1/users/{user_id}/devices"


def etag_of(response):
    return response.headers["etag"]


def if_none_match(headers, etag):
    return {**headers, "If-None-Match": etag}


def test_the_own_list_marks_the_calling_device(http, active_user, device, bearer):
    other = make_device(active_user, registration_id=2)

    body = http.get(DEVICES_URL, headers=bearer(active_user, device)).json()

    flags = {d["device_id"]: d["this_device"] for d in body["devices"]}
    assert flags[str(device.id)] is True
    assert flags[str(other.id)] is False


def test_the_own_list_returns_the_label_blob_verbatim(http, active_user, device, bearer):
    publish_identity(active_user)
    http.post(
        DEVICES_URL,
        json=register_payload(label_blob=label_blob()),
        headers=bearer(active_user, device),
    )

    body = http.get(DEVICES_URL, headers=bearer(active_user, device)).json()

    labels = [d["label_blob"] for d in body["devices"] if d["label_blob"]]
    assert labels == [label_blob()]


def test_the_own_list_hides_revoked_devices(http, active_user, device, bearer):
    dead = make_device(active_user, registration_id=9, revoked_date=timezone.now().date())

    body = http.get(DEVICES_URL, headers=bearer(active_user, device)).json()

    assert str(dead.id) not in {d["device_id"] for d in body["devices"]}


def test_a_matching_if_none_match_gets_a_304(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    etag = etag_of(http.get(DEVICES_URL, headers=headers))

    again = http.get(DEVICES_URL, headers=if_none_match(headers, etag))

    assert again.status_code == 304
    assert again.content == b""


def test_adding_a_device_changes_the_own_list_etag(http, active_user, device, bearer):
    publish_identity(active_user)
    headers = bearer(active_user, device)
    before = etag_of(http.get(DEVICES_URL, headers=headers))

    http.post(DEVICES_URL, json=register_payload(), headers=headers)

    assert etag_of(http.get(DEVICES_URL, headers=headers)) != before


def test_revoking_a_device_changes_the_own_list_etag(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    doomed = make_device(active_user, registration_id=3)
    before = etag_of(http.get(DEVICES_URL, headers=headers))

    http.delete(f"{DEVICES_URL}/{doomed.id}", headers=headers)

    assert etag_of(http.get(DEVICES_URL, headers=headers)) != before


def test_the_peer_list_exposes_only_public_identity(
    http, active_user, device, bearer, peer, peer_device
):
    response = http.get(peer_url(peer.id), headers=bearer(active_user, device))

    assert response.status_code == 200
    entry = response.json()["devices"][0]
    assert set(entry) == {
        "device_id",
        "ik_pub",
        "registration_id",
        "cross_sig",
        "bundle_version",
    }
    assert base64.b64decode(entry["ik_pub"]) == bytes(peer_device.ik_pub)
    # No label, no dates, no activity; those belong to the account owner.
    assert "label_blob" not in entry
    assert "spk_pub" not in entry


def test_the_peer_list_carries_an_etag_and_honours_if_none_match(
    http, active_user, device, bearer, peer, peer_device
):
    headers = bearer(active_user, device)
    first = http.get(peer_url(peer.id), headers=headers)

    again = http.get(peer_url(peer.id), headers=if_none_match(headers, etag_of(first)))

    assert first.json()["etag"] == etag_of(first)
    assert again.status_code == 304


def test_revoking_a_peer_device_changes_the_peer_etag(
    http, active_user, device, bearer, peer, peer_device
):
    headers = bearer(active_user, device)
    before = etag_of(http.get(peer_url(peer.id), headers=headers))
    peer_device.revoked_date = timezone.now().date()
    peer_device.save(update_fields=["revoked_date"])

    assert etag_of(http.get(peer_url(peer.id), headers=headers)) != before


def test_deactivating_a_peer_hides_its_devices_and_changes_the_etag(
    http, active_user, device, bearer, peer, peer_device
):
    """Without `user__is_active` in the ETag, a deactivated account keeps its old tag
    and every polling peer sits on a 304 holding devices the list no longer returns."""
    headers = bearer(active_user, device)
    before = etag_of(http.get(peer_url(peer.id), headers=headers))
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    after = http.get(peer_url(peer.id), headers=headers)

    assert after.json()["devices"] == []
    assert etag_of(after) != before


def test_the_etag_does_not_leak_that_a_peer_revoked_devices(
    http, active_user, device, bearer, peer
):
    """Both accounts serve an empty device list, so both must serve the same ETag;
    otherwise the tag is a side channel for device churn the peer list hides."""
    headers = bearer(active_user, device)
    make_device(peer, registration_id=1, revoked_date=timezone.now().date())

    unknown = http.get(peer_url(uuid.uuid4()), headers=headers)
    all_revoked = http.get(peer_url(peer.id), headers=headers)

    assert unknown.json()["devices"] == all_revoked.json()["devices"] == []
    assert etag_of(unknown) == etag_of(all_revoked)


def test_an_unknown_user_is_indistinguishable_from_one_with_no_devices(
    http, active_user, device, bearer, peer
):
    headers = bearer(active_user, device)

    unknown = http.get(peer_url(uuid.uuid4()), headers=headers)
    empty = http.get(peer_url(peer.id), headers=headers)

    assert unknown.status_code == empty.status_code == 200
    assert unknown.json()["devices"] == empty.json()["devices"] == []
