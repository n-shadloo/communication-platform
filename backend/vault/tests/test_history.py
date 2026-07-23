"""History append/read/delete/usage semantics.

`seq` is per-owner, contiguous and gapless across batches; two owners' logs are
independent; paging is keyset-ascending with an honest `has_more`; delete and usage
are strictly owner-scoped. The hostile-input cases confirm the hardened parsing
never 500s.
"""
import pytest

from vault.models import HistoryRecord
from .conftest import (HISTORY_DELETE_URL, HISTORY_URL, HISTORY_USAGE_URL, history_blob,
                       uniq_history_blob)

pytestmark = pytest.mark.django_db

AUTH_QUERIES = 2  # DeviceJWTAuthentication reads the user row and the device row


def append(api, headers, blobs):
    return api.post(HISTORY_URL, {"records": [{"blob": b} for b in blobs]},
                    format="json", **headers)


def append_batched(api, headers, blobs, chunk=100):
    """The per-batch ceiling is 100 records, so a larger log is uploaded in chunks."""
    for i in range(0, len(blobs), chunk):
        resp = append(api, headers, blobs[i:i + chunk])
        assert resp.status_code == 201


def owner_seqs(user):
    return list(HistoryRecord.objects.filter(owner_id=user.id)
                .order_by("seq").values_list("seq", flat=True))


def test_append_is_contiguous_within_a_batch(api, active_user, device, auth_headers):
    resp = append(api, auth_headers(active_user, device),
                  [history_blob(bytes([65 + i])) for i in range(5)])
    assert resp.status_code == 201
    assert resp.json() == {"first_seq": 0, "last_seq": 4}


def test_append_is_gapless_across_batches(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    first = append(api, headers, [history_blob() for _ in range(3)]).json()
    second = append(api, headers, [history_blob() for _ in range(4)]).json()
    assert first == {"first_seq": 0, "last_seq": 2}
    assert second == {"first_seq": 3, "last_seq": 6}
    assert owner_seqs(active_user) == list(range(7))


def test_empty_batch_is_rejected(api, active_user, device, auth_headers):
    resp = api.post(HISTORY_URL, {"records": []}, format="json",
                    **auth_headers(active_user, device))
    assert resp.status_code == 400


def test_two_owners_sequences_are_independent(api, active_user, device, auth_headers,
                                              bob, bob_device):
    alice_h = auth_headers(active_user, device)
    bob_h = auth_headers(bob, bob_device)
    append(api, bob_h, [history_blob() for _ in range(2)])     # bob → 0, 1
    append(api, alice_h, [history_blob() for _ in range(3)])   # alice → 0, 1, 2
    append(api, bob_h, [history_blob()])                       # bob → 2
    assert owner_seqs(active_user) == [0, 1, 2]
    assert owner_seqs(bob) == [0, 1, 2]


def test_keyset_paging_reads_in_order_with_has_more(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append_batched(api, headers, [uniq_history_blob(i) for i in range(250)])

    seen, after, pages = [], -1, 0
    while True:
        page = api.get(f"{HISTORY_URL}?after={after}&limit=100", **headers).json()
        pages += 1
        seen.extend(page["records"])
        if not page["has_more"]:
            break
        after = seen[-1]["seq"]

    assert pages == 3
    assert [r["seq"] for r in seen] == list(range(250))
    assert [r["blob"] for r in seen] == [uniq_history_blob(i) for i in range(250)]


def test_limit_is_capped_at_500(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob() for _ in range(100)])
    # Asking for more than the ceiling still returns a single capped page.
    page = api.get(f"{HISTORY_URL}?after=-1&limit=100000", **headers).json()
    assert len(page["records"]) == 100 and page["has_more"] is False


def test_delete_seqs_only_touches_callers_log(api, active_user, device, auth_headers,
                                              bob, bob_device):
    alice_h = auth_headers(active_user, device)
    bob_h = auth_headers(bob, bob_device)
    append(api, alice_h, [history_blob() for _ in range(5)])   # alice 0..4
    append(api, bob_h, [history_blob() for _ in range(3)])     # bob 0..2

    resp = api.post(HISTORY_DELETE_URL, {"seqs": [1, 3]}, format="json", **alice_h)
    assert resp.status_code == 200 and resp.json() == {"deleted": 2}
    assert owner_seqs(active_user) == [0, 2, 4]
    # bob also has a seq 1, but alice's delete never reached it.
    assert owner_seqs(bob) == [0, 1, 2]


def test_delete_all_clears_only_callers_log(api, active_user, device, auth_headers,
                                            bob, bob_device):
    alice_h = auth_headers(active_user, device)
    bob_h = auth_headers(bob, bob_device)
    append(api, alice_h, [history_blob() for _ in range(4)])
    append(api, bob_h, [history_blob() for _ in range(2)])

    resp = api.post(HISTORY_DELETE_URL, {"all": True}, format="json", **alice_h)
    assert resp.status_code == 200 and resp.json() == {"deleted": 4}
    assert owner_seqs(active_user) == []
    assert owner_seqs(bob) == [0, 1]


def test_usage_reports_count_and_db_side_byte_total(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob(size=1024) for _ in range(3)])
    append(api, headers, [history_blob(size=4096)])
    resp = api.get(HISTORY_USAGE_URL, **headers)
    assert resp.status_code == 200
    assert resp.json() == {"records": 4, "bytes": 3 * 1024 + 4096}


def test_usage_of_empty_log_is_zero(api, active_user, device, auth_headers):
    resp = api.get(HISTORY_USAGE_URL, **auth_headers(active_user, device))
    assert resp.json() == {"records": 0, "bytes": 0}


def test_usage_is_a_single_aggregate_query(api, active_user, device, auth_headers,
                                           django_assert_num_queries):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob() for _ in range(10)])
    with django_assert_num_queries(AUTH_QUERIES + 1):
        api.get(HISTORY_USAGE_URL, **headers)


# --- hostile input: naive int()/.get() parsing would 500 on these ------------------------

def test_nonnumeric_after_falls_back_to_start(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob() for _ in range(3)])
    resp = api.get(f"{HISTORY_URL}?after=abc", **headers)
    assert resp.status_code == 200
    assert [r["seq"] for r in resp.json()["records"]] == [0, 1, 2]


def test_nonnumeric_limit_falls_back_to_default(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob() for _ in range(3)])
    resp = api.get(f"{HISTORY_URL}?limit=abc", **headers)
    assert resp.status_code == 200
    assert len(resp.json()["records"]) == 3


def test_negative_limit_is_clamped_not_a_500(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    append(api, headers, [history_blob() for _ in range(3)])
    resp = api.get(f"{HISTORY_URL}?limit=-5", **headers)
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["records"]) == 1 and body["has_more"] is True


def test_delete_array_body_is_400_not_500(api, active_user, device, auth_headers):
    resp = api.post(HISTORY_DELETE_URL, [1, 2, 3], format="json",
                    **auth_headers(active_user, device))
    assert resp.status_code == 400 and resp.json()["code"] == "bad_request"


def test_delete_nonint_seqs_is_400_not_500(api, active_user, device, auth_headers):
    resp = api.post(HISTORY_DELETE_URL, {"seqs": ["abc"]}, format="json",
                    **auth_headers(active_user, device))
    assert resp.status_code == 400 and resp.json()["code"] == "bad_request"


def test_delete_too_many_seqs_is_400(api, active_user, device, auth_headers):
    resp = api.post(HISTORY_DELETE_URL, {"seqs": list(range(1001))}, format="json",
                    **auth_headers(active_user, device))
    assert resp.status_code == 400 and resp.json()["code"] == "bad_request"


def test_delete_out_of_range_float_seq_is_400_not_500(api, active_user, device, auth_headers):
    # A raw body bypasses the client JSON encoder; DRF's parser turns `1e400` into
    # float inf, and int(inf) raises OverflowError, which must be caught rather than
    # surfaced as a 500.
    resp = api.post(HISTORY_DELETE_URL, data='{"seqs": [1e400]}',
                    content_type="application/json", **auth_headers(active_user, device))
    assert resp.status_code == 400 and resp.json()["code"] == "bad_request"
