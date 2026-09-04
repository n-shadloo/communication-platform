import base64

import pytest
from django.utils import timezone

from .conftest import (
    DEVICES_URL,
    label_blob,
    make_device,
    publish_identity,
    register_payload,
)

pytestmark = pytest.mark.django_db


def peer_url(user_id):
    return f"/api/v1/users/{user_id}/devices"


def test_the_own_list_marks_the_calling_device(api, active_user, device, auth_headers):
    other = make_device(active_user, registration_id=2)

    body = api.get(DEVICES_URL, **auth_headers(active_user, device)).json()

    flags = {d["device_id"]: d["this_device"] for d in body["devices"]}
    assert flags[str(device.id)] is True
    assert flags[str(other.id)] is False


def test_the_own_list_returns_the_label_blob_verbatim(
    api, active_user, device, auth_headers
):
    publish_identity(active_user)
    api.post(
        DEVICES_URL,
        register_payload(label_blob=label_blob()),
        format="json",
        **auth_headers(active_user, device),
    )

    body = api.get(DEVICES_URL, **auth_headers(active_user, device)).json()

    labels = [d["label_blob"] for d in body["devices"] if d["label_blob"]]
    assert labels == [label_blob()]


def test_the_own_list_hides_revoked_devices(api, active_user, device, auth_headers):
    dead = make_device(active_user, registration_id=9, revoked_date=timezone.now().date())

    body = api.get(DEVICES_URL, **auth_headers(active_user, device)).json()

    assert str(dead.id) not in {d["device_id"] for d in body["devices"]}


def test_a_matching_if_none_match_gets_a_304(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    etag = api.get(DEVICES_URL, **headers)["ETag"]

    again = api.get(DEVICES_URL, HTTP_IF_NONE_MATCH=etag, **headers)

    assert again.status_code == 304


def test_adding_a_device_changes_the_own_list_etag(
    api, active_user, device, auth_headers
):
    publish_identity(active_user)
    headers = auth_headers(active_user, device)
    before = api.get(DEVICES_URL, **headers)["ETag"]

    api.post(DEVICES_URL, register_payload(), format="json", **headers)

    assert api.get(DEVICES_URL, **headers)["ETag"] != before


def test_revoking_a_device_changes_the_own_list_etag(
    api, active_user, device, auth_headers
):
    headers = auth_headers(active_user, device)
    doomed = make_device(active_user, registration_id=3)
    before = api.get(DEVICES_URL, **headers)["ETag"]

    api.delete(f"{DEVICES_URL}/{doomed.id}", **headers)

    assert api.get(DEVICES_URL, **headers)["ETag"] != before


def test_the_peer_list_exposes_only_public_identity(
    api, active_user, device, auth_headers, peer, peer_device
):
    response = api.get(peer_url(peer.id), **auth_headers(active_user, device))

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
    api, active_user, device, auth_headers, peer, peer_device
):
    headers = auth_headers(active_user, device)
    first = api.get(peer_url(peer.id), **headers)

    again = api.get(peer_url(peer.id), HTTP_IF_NONE_MATCH=first["ETag"], **headers)

    assert first.json()["etag"] == first["ETag"]
    assert again.status_code == 304


def test_revoking_a_peer_device_changes_the_peer_etag(
    api, active_user, device, auth_headers, peer, peer_device
):
    headers = auth_headers(active_user, device)
    before = api.get(peer_url(peer.id), **headers)["ETag"]
    peer_device.revoked_date = timezone.now().date()
    peer_device.save(update_fields=["revoked_date"])

    assert api.get(peer_url(peer.id), **headers)["ETag"] != before


def test_deactivating_a_peer_hides_its_devices_and_changes_the_etag(
    api, active_user, device, auth_headers, peer, peer_device
):
    """Without `user__is_active` in the ETag, a deactivated account keeps its old tag
    and every polling peer sits on a 304 holding devices the list no longer returns."""
    headers = auth_headers(active_user, device)
    before = api.get(peer_url(peer.id), **headers)["ETag"]
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    after = api.get(peer_url(peer.id), **headers)

    assert after.json()["devices"] == []
    assert after["ETag"] != before


def test_the_etag_does_not_leak_that_a_peer_revoked_devices(
    api, active_user, device, auth_headers, peer
):
    """Both accounts serve an empty device list, so both must serve the same ETag;
    otherwise the tag is a side channel for device churn the peer list hides."""
    import uuid

    headers = auth_headers(active_user, device)
    make_device(peer, registration_id=1, revoked_date=timezone.now().date())

    unknown = api.get(peer_url(uuid.uuid4()), **headers)
    all_revoked = api.get(peer_url(peer.id), **headers)

    assert unknown.json()["devices"] == all_revoked.json()["devices"] == []
    assert unknown["ETag"] == all_revoked["ETag"]


def test_an_unknown_user_is_indistinguishable_from_one_with_no_devices(
    api, active_user, device, auth_headers, peer
):
    import uuid

    headers = auth_headers(active_user, device)

    unknown = api.get(peer_url(uuid.uuid4()), **headers)
    empty = api.get(peer_url(peer.id), **headers)

    assert unknown.status_code == empty.status_code == 200
    assert unknown.json()["devices"] == empty.json()["devices"] == []
