"""Query-shape guards for the device endpoints.

These lock in the shape: the list endpoints must stay constant-query however many
devices an account has, and the claim must stay one bounded set of queries per target
device, never one per stored prekey.

Counts include the per-request auth queries `DeviceJWTAuthentication` makes and,
under pytest's per-test transaction, a SAVEPOINT/RELEASE pair per `atomic()` block,
which in production is a real BEGIN/COMMIT instead. Headers are always built before
the assertion block: `auth_headers` mints a refresh token, which writes an
outstanding-token row of its own.
"""

import pytest

from .conftest import DEVICES_URL, make_device, pubkey, stock_keypackages, stock_prekeys

pytestmark = pytest.mark.django_db

AUTH_QUERIES = 2  # the user row and the device row
# Live device ids + the device-log head (an ETag input since the log landed).
# Constant: neither scales with the device count or the log length.
ETAG_QUERY = 2
LIST_QUERY = 1
# savepoint, locked select, delete, release
CLAIM_QUERIES_PER_DEVICE = 4


def peer_url(user_id):
    return f"/api/v1/users/{user_id}/devices"


def claim_url(user_id):
    return f"/api/v1/users/{user_id}/keys/claim"


@pytest.mark.parametrize("device_count", [1, 5, 10])
def test_the_own_device_list_is_constant_query(
    api, active_user, device, auth_headers, django_assert_num_queries, device_count
):
    for i in range(device_count - 1):
        make_device(active_user, registration_id=400 + i)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + ETAG_QUERY + LIST_QUERY):
        response = api.get(DEVICES_URL, **headers)

    assert len(response.json()["devices"]) == device_count


@pytest.mark.parametrize("device_count", [1, 5, 10])
def test_the_peer_device_list_is_constant_query(
    api,
    active_user,
    device,
    auth_headers,
    peer,
    peer_device,
    django_assert_num_queries,
    device_count,
):
    for i in range(device_count - 1):
        make_device(peer, registration_id=500 + i)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + ETAG_QUERY + LIST_QUERY):
        response = api.get(peer_url(peer.id), **headers)

    assert len(response.json()["devices"]) == device_count


def test_a_304_skips_the_list_query_entirely(
    api, active_user, device, auth_headers, django_assert_num_queries
):
    headers = auth_headers(active_user, device)
    etag = api.get(DEVICES_URL, **headers)["ETag"]

    with django_assert_num_queries(AUTH_QUERIES + ETAG_QUERY):
        response = api.get(DEVICES_URL, HTTP_IF_NONE_MATCH=etag, **headers)

    assert response.status_code == 304


@pytest.mark.parametrize("pool_size", [1, 20, 200])
def test_a_claim_does_not_scale_with_the_prekey_pool(
    api,
    active_user,
    device,
    auth_headers,
    peer,
    peer_device,
    django_assert_num_queries,
    pool_size,
):
    """The N+1 that would matter most: claiming must cost the same whether the device
    stores one prekey or two hundred."""
    stock_prekeys(peer_device, pool_size)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1 + CLAIM_QUERIES_PER_DEVICE):
        response = api.post(claim_url(peer.id), {}, format="json", **headers)

    assert "otpk" in response.json()["bundles"][0]


@pytest.mark.parametrize("device_count", [1, 3, 6])
def test_a_claim_costs_one_bounded_transaction_per_target_device(
    api,
    active_user,
    device,
    auth_headers,
    peer,
    peer_device,
    django_assert_num_queries,
    device_count,
):
    """The response is a bundle per device, so the per-device transaction is
    inherent; what must not happen is a query per prekey or a second lookup per
    device."""
    for i in range(device_count - 1):
        stock_prekeys(make_device(peer, registration_id=600 + i), 2)
    stock_prekeys(peer_device, 2)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(
        AUTH_QUERIES + 1 + CLAIM_QUERIES_PER_DEVICE * device_count
    ):
        response = api.post(claim_url(peer.id), {}, format="json", **headers)

    assert len(response.json()["bundles"]) == device_count


def test_an_exhausted_pool_costs_one_query_less(
    api, active_user, device, auth_headers, peer, peer_device, django_assert_num_queries
):
    """No prekey to delete, so the delete never runs."""
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1 + CLAIM_QUERIES_PER_DEVICE - 1):
        response = api.post(claim_url(peer.id), {}, format="json", **headers)

    assert "otpk" not in response.json()["bundles"][0]


@pytest.mark.parametrize("store_size", [1, 50, 100])
def test_a_keypackage_claim_does_not_scale_with_the_store(
    api,
    active_user,
    device,
    auth_headers,
    peer,
    peer_device,
    django_assert_num_queries,
    store_size,
):
    stock_keypackages(peer_device, store_size)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1 + CLAIM_QUERIES_PER_DEVICE):
        response = api.post(
            f"/api/v1/users/{peer.id}/keypackages/claim", {}, format="json", **headers
        )

    assert len(response.json()["keypackages"]) == 1


@pytest.mark.parametrize("log_length", [0, 5, 60])
def test_the_device_list_stays_constant_query_as_the_log_grows(
    api, active_user, device, auth_headers, django_assert_num_queries, log_length
):
    """The ETag reads only the head record, so a longer log must not add queries
    (or the ETag becomes a per-poll scan of the whole log)."""
    from devices.models import DeviceLogRecord

    DeviceLogRecord.objects.bulk_create(
        [
            DeviceLogRecord(user=active_user, seq=i, blob=b"r" * 256)
            for i in range(log_length)
        ]
    )
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + ETAG_QUERY + LIST_QUERY):
        response = api.get(DEVICES_URL, **headers)

    expected_head = log_length - 1 if log_length else None
    assert response.json()["log_head_seq"] == expected_head


def test_cross_signing_fields_ride_the_existing_queries(
    api, active_user, device, auth_headers, peer, peer_device, django_assert_num_queries
):
    """cross_sig and bundle_version are columns on the rows the list and claim
    already fetch, so surfacing them must not add a query."""
    peer_device.cross_sig = b"\xc5" * 64
    peer_device.bundle_version = 4
    peer_device.save(update_fields=["cross_sig", "bundle_version"])
    stock_prekeys(peer_device, 1)
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + ETAG_QUERY + LIST_QUERY):
        listed = api.get(peer_url(peer.id), **headers)
    with django_assert_num_queries(AUTH_QUERIES + 1 + CLAIM_QUERIES_PER_DEVICE):
        claimed = api.post(claim_url(peer.id), {}, format="json", **headers)

    assert listed.json()["devices"][0]["cross_sig"] is not None
    assert claimed.json()["bundles"][0]["bundle_version"] == 4


@pytest.mark.parametrize("pool_size", [0, 50, 199])
def test_replenishment_is_constant_query(
    api, active_user, device, auth_headers, django_assert_num_queries, pool_size
):
    """The cap check must not walk the stored pool."""
    stock_prekeys(device, pool_size, start=1000)
    headers = auth_headers(active_user, device)
    body = {"otpks": [{"key_id": 1, "pub": pubkey()}]}
    # savepoint, device lock, cap count, bulk insert, recount, release
    with django_assert_num_queries(AUTH_QUERIES + 6):
        response = api.put(
            f"{DEVICES_URL}/{device.id}/prekeys", body, format="json", **headers
        )

    assert response.status_code == 200


def test_registration_is_constant_query_whatever_the_payload(
    api, active_user, device, auth_headers, django_assert_num_queries
):
    """200 prekeys and 100 key packages go in as two bulk inserts, not 300."""
    from .conftest import publish_identity, register_payload

    publish_identity(active_user)
    headers = auth_headers(active_user, device)
    payload = register_payload(otpks=200, keypackages=100)
    # savepoint, user lock, cap count, identity-exists check, device insert,
    # otpk bulk, keypackage bulk, release, then the refresh-token row the issued
    # pair writes
    with django_assert_num_queries(AUTH_QUERIES + 9):
        response = api.post(DEVICES_URL, payload, format="json", **headers)

    assert response.status_code == 201
