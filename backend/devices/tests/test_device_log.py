"""Client-signed append-only device-list log.

The server assigns sequence numbers and serves bytes back verbatim; everything
that makes the log meaningful — the hash chain, the signatures, comparing heads
and raising a fork alarm — is client-side and specified in CLIENT_CONTRACT.md.
The adversarial test here proves the server-side half: no chain validation, no
repair, no smoothing.
"""

import base64
import threading

import pytest
from django.core.cache import cache
from django.db import connections
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from accounts.models import User
from api.auth import issue_full
from core.buckets import DEVICELOG_BUCKETS
from devices.models import DeviceLogRecord

from .conftest import DEVICES_URL, PASSWORD, make_device

pytestmark = pytest.mark.django_db

LOG_URL = "/api/v1/me/devicelog"

CONCURRENT_APPENDS = 12


def peer_log_url(user_id, query=""):
    return f"/api/v1/users/{user_id}/devicelog{query}"


def log_blob(filler=b"R", size=None):
    size = size or min(DEVICELOG_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def test_appends_assign_seq_and_read_back_byte_identical(
    api, active_user, device, auth_headers, peer, peer_device
):
    mine = auth_headers(active_user, device)
    blobs = [log_blob(bytes([65 + i])) for i in range(3)]

    posted = api.post(
        LOG_URL, {"records": [{"blob": b} for b in blobs]}, format="json", **mine
    )

    assert posted.status_code == 201
    assert posted.json() == {"first_seq": 0, "last_seq": 2}
    page = api.get(peer_log_url(active_user.id), **auth_headers(peer, peer_device)).json()
    assert [r["blob"] for r in page["records"]] == blobs
    assert [r["seq"] for r in page["records"]] == [0, 1, 2]
    assert page["head_seq"] == 2
    assert page["has_more"] is False


def test_keyset_paging_clamps_bad_cursors_and_limits(
    api, active_user, device, auth_headers, peer, peer_device
):
    mine = auth_headers(active_user, device)
    api.post(
        LOG_URL,
        {"records": [{"blob": log_blob(bytes([65 + i]))} for i in range(5)]},
        format="json",
        **mine,
    )
    theirs = auth_headers(peer, peer_device)

    page = api.get(peer_log_url(active_user.id, "?after=1&limit=2"), **theirs).json()
    assert [r["seq"] for r in page["records"]] == [2, 3]
    assert page["has_more"] is True
    assert page["head_seq"] == 4

    # A junk cursor falls back to the start; a junk limit falls back to the cap.
    junk = api.get(peer_log_url(active_user.id, "?after=abc&limit=zzz"), **theirs).json()
    assert [r["seq"] for r in junk["records"]] == [0, 1, 2, 3, 4]


def test_an_off_bucket_record_is_rejected_without_echoing(
    api, active_user, device, auth_headers
):
    off_bucket = base64.b64encode(b"x" * 300).decode()

    response = api.post(
        LOG_URL,
        {"records": [{"blob": off_bucket}]},
        format="json",
        **auth_headers(active_user, device),
    )

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"
    assert off_bucket not in response.content.decode()
    assert DeviceLogRecord.objects.count() == 0


def test_more_than_fifty_records_per_append_are_rejected(
    api, active_user, device, auth_headers
):
    body = {"records": [{"blob": log_blob()} for _ in range(51)]}

    response = api.post(LOG_URL, body, format="json", **auth_headers(active_user, device))

    assert response.status_code == 400


def test_a_log_append_changes_the_device_list_etag(
    api, active_user, device, auth_headers
):
    headers = auth_headers(active_user, device)
    before = api.get(DEVICES_URL, **headers)["ETag"]

    api.post(LOG_URL, {"records": [{"blob": log_blob()}]}, format="json", **headers)

    after = api.get(DEVICES_URL, **headers)
    assert after["ETag"] != before
    assert after.json()["log_head_seq"] == 0
    # And once the client holds the new tag, polling returns 304 again.
    assert (
        api.get(DEVICES_URL, HTTP_IF_NONE_MATCH=after["ETag"], **headers).status_code
        == 304
    )


def test_the_peer_list_surfaces_the_log_head(
    api, active_user, device, auth_headers, peer, peer_device
):
    api.post(
        LOG_URL,
        {"records": [{"blob": log_blob()}, {"blob": log_blob(b"S")}]},
        format="json",
        **auth_headers(peer, peer_device),
    )

    body = api.get(
        f"/api/v1/users/{peer.id}/devices", **auth_headers(active_user, device)
    ).json()

    assert body["log_head_seq"] == 1


def test_a_deactivated_users_log_is_hidden(
    api, active_user, device, auth_headers, peer, peer_device
):
    api.post(
        LOG_URL,
        {"records": [{"blob": log_blob()}]},
        format="json",
        **auth_headers(peer, peer_device),
    )
    peer.is_active = False
    peer.save(update_fields=["is_active"])

    page = api.get(peer_log_url(peer.id), **auth_headers(active_user, device)).json()

    assert page["records"] == []
    assert page["head_seq"] is None


def test_a_non_linking_record_is_accepted_and_served_unchanged(
    api, active_user, device, auth_headers, peer, peer_device
):
    """Server-side half of "equivocation detected via gossip": a record whose
    prev_hash is deliberate garbage must be accepted and served byte-identically,
    in order, proving no server-side chain validation, repair, reordering, or
    dropping exists — which is what makes detection genuinely client-side. The
    other half — two clients comparing heads and raising a fork alarm on mismatch
    — is client behaviour and belongs to CLIENT_CONTRACT.md."""
    mine = auth_headers(active_user, device)
    api.post(LOG_URL, {"records": [{"blob": log_blob(b"A")}]}, format="json", **mine)
    # Not a hash of anything: a chain-validating server would have to reject it.
    garbage = log_blob(b"\xff")

    posted = api.post(LOG_URL, {"records": [{"blob": garbage}]}, format="json", **mine)

    assert posted.status_code == 201
    page = api.get(peer_log_url(active_user.id), **auth_headers(peer, peer_device)).json()
    assert [r["blob"] for r in page["records"]] == [log_blob(b"A"), garbage]
    assert page["head_seq"] == 1


class DeviceLogAppendConcurrencyTests(TransactionTestCase):
    """Mirror of vault/tests/test_concurrency.py: seq assignment rests on a real
    committed user-row lock racing other transactions, which a wrapping test
    transaction would hide."""

    def setUp(self):
        cache.clear()
        self.owner = User.objects.create_user(
            username="alice", password=PASSWORD, is_active=True
        )
        self.device = make_device(self.owner, 1)
        access, _refresh = issue_full(self.owner, self.device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def test_parallel_appends_never_duplicate_or_gap_seq(self):
        failures = []
        start = threading.Barrier(CONCURRENT_APPENDS)

        def append_one():
            try:
                start.wait(timeout=10)
                resp = APIClient().post(
                    LOG_URL,
                    {"records": [{"blob": log_blob()}]},
                    format="json",
                    **self.headers,
                )
                if resp.status_code != 201:
                    failures.append(resp.status_code)
            except Exception as exc:  # a seq collision surfaces as IntegrityError
                failures.append(repr(exc))
            finally:
                connections.close_all()

        threads = [threading.Thread(target=append_one) for _ in range(CONCURRENT_APPENDS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(failures, [])
        seqs = sorted(
            DeviceLogRecord.objects.filter(user_id=self.owner.id).values_list(
                "seq", flat=True
            )
        )
        self.assertEqual(seqs, list(range(CONCURRENT_APPENDS)))

    def test_the_unique_constraint_would_catch_a_duplicate_seq(self):
        """Guards the guard: without (user, seq) unique the race test above could
        pass vacuously if the counter logic were ever broken."""
        DeviceLogRecord.objects.create(user=self.owner, seq=0, blob=b"a" * 256)
        with self.assertRaises(Exception):
            DeviceLogRecord.objects.create(user=self.owner, seq=0, blob=b"b" * 256)
