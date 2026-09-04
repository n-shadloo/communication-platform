import base64
import uuid

import pytest
from django.utils import timezone

from core.buckets import DEVICELOG_BUCKETS
from devices.models import Device, DeviceLogRecord

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


def log_url():
    return "/api/v1/me/devicelog"


def a_log_record():
    size = min(DEVICELOG_BUCKETS)
    return {"records": [{"blob": base64.b64encode(b"R" * size).decode()}]}


def test_a_peer_on_a_stale_tag_is_served_the_new_head_rather_than_a_304(
    http, active_user, device, bearer, peer, peer_device
):
    """The failure `_device_list_etag` names in its own comment: the head record's
    hash is an input to the tag precisely so a log append cannot leave a polling
    peer sitting on a 304, holding a head it is supposed to gossip about."""
    watcher = bearer(peer, peer_device)
    url = peer_url(active_user.id)
    held = etag_of(http.get(url, headers=watcher))

    http.post(log_url(), json=a_log_record(), headers=bearer(active_user, device))

    fresh = http.get(url, headers=if_none_match(watcher, held))
    assert fresh.status_code == 200
    assert fresh.json()["log_head_seq"] == 0
    assert etag_of(fresh) != held
    # And the poller that now holds the new tag is back to a cheap 304.
    caught_up = http.get(url, headers=if_none_match(watcher, etag_of(fresh)))
    assert caught_up.status_code == 304
    assert caught_up.content == b""


def test_a_change_no_one_polled_for_still_moves_the_tag(
    http, active_user, device, bearer
):
    """The tag is a function of stored state, not of what has been served since the
    last request: the panel's revoke action and the TTL prune both write without a
    request, and a tag that only moved on the API's own writes would leave every
    poller on a 304 across those."""
    headers = bearer(active_user, device)
    doomed = make_device(active_user, registration_id=31)
    held = etag_of(http.get(DEVICES_URL, headers=headers))

    # Written straight to the rows, with no request touching the ETag path.
    Device.objects.filter(pk=doomed.pk).update(revoked_date=timezone.now().date())
    DeviceLogRecord.objects.create(
        user=active_user, seq=0, blob=b"R" * min(DEVICELOG_BUCKETS)
    )

    stale_poll = http.get(DEVICES_URL, headers=if_none_match(headers, held))
    assert stale_poll.status_code == 200
    assert etag_of(stale_poll) != held
    assert stale_poll.json()["log_head_seq"] == 0
    assert str(doomed.id) not in {d["device_id"] for d in stale_poll.json()["devices"]}


def test_the_tag_covers_the_live_set_and_the_log_head_and_not_the_label(
    http, active_user, device, bearer
):
    """The inputs `devices/API.md` publishes, stated as the difference they make. A
    relabel is deliberately outside them, so a sibling polling with `If-None-Match`
    keeps a 304 and does not see a new label until the device set or the log moves —
    which is what the published tag definition means in practice."""
    headers = bearer(active_user, device)
    before = etag_of(http.get(DEVICES_URL, headers=headers))

    relabelled = http.put(
        f"{DEVICES_URL}/{device.id}", json={"label_blob": label_blob()}, headers=headers
    )

    assert relabelled.status_code == 200
    assert etag_of(http.get(DEVICES_URL, headers=headers)) == before
    assert (
        http.get(DEVICES_URL, headers=if_none_match(headers, before)).status_code == 304
    )

    http.post(log_url(), json=a_log_record(), headers=headers)

    assert etag_of(http.get(DEVICES_URL, headers=headers)) != before


def test_one_accounts_tag_is_not_honoured_on_another_accounts_list(
    http, active_user, device, bearer, peer, peer_device
):
    """The tag is per account. Presenting one account's tag against another's list
    must serve the list, or a caller could be told "nothing changed" about a peer it
    has never fetched."""
    headers = bearer(active_user, device)
    mine = etag_of(http.get(DEVICES_URL, headers=headers))

    theirs = http.get(peer_url(peer.id), headers=if_none_match(headers, mine))

    assert theirs.status_code == 200
    assert etag_of(theirs) != mine
    assert {d["device_id"] for d in theirs.json()["devices"]} == {str(peer_device.id)}


def test_the_own_list_orders_by_creation_then_id(http, active_user, device, bearer):
    """`created_date` is day-coarse, so it alone leaves same-day devices in an
    arbitrary order that can shuffle between polls; the id breaks the tie, and the
    order is what a client's device table renders."""
    siblings = [make_device(active_user, registration_id=40 + i) for i in range(4)]
    expected = sorted(str(row.id) for row in [device, *siblings])

    listed = http.get(DEVICES_URL, headers=bearer(active_user, device)).json()

    assert [entry["device_id"] for entry in listed["devices"]] == expected


def test_the_peer_list_orders_by_id(http, active_user, device, bearer, peer, peer_device):
    """Peers see no dates at all, so id is the whole order — and it has to be an
    order, or a client diffing two polls sees churn that never happened."""
    others = [make_device(peer, registration_id=50 + i) for i in range(4)]
    expected = sorted(str(row.id) for row in [peer_device, *others])

    listed = http.get(peer_url(peer.id), headers=bearer(active_user, device)).json()

    assert [entry["device_id"] for entry in listed["devices"]] == expected
