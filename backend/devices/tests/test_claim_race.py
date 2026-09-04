"""Single consumption under concurrency.

`transaction=True` because the point is real committed transactions racing: the
claim rests on `SELECT ... LIMIT 1 FOR UPDATE SKIP LOCKED` plus a delete inside
the same transaction, and a wrapping test transaction would hide exactly that.
"""

import threading

import pytest
from django.db import connections, transaction

from devices.models import OneTimePrekey

from .conftest import connect_then_wait, make_device, stock_prekeys

pytestmark = pytest.mark.django_db(transaction=True)

CONCURRENT_CLAIMS = 12


@pytest.fixture
def owner_device(peer):
    """The account whose one-time prekeys every thread will race for."""
    return make_device(peer, registration_id=2)


def storm(new_http, url, headers, harvest):
    """Fire CONCURRENT_CLAIMS requests at once and collect what each got."""
    start = threading.Barrier(CONCURRENT_CLAIMS)
    received, failures = [], []
    lock = threading.Lock()

    def claim():
        try:
            connect_then_wait(start)
            response = new_http().post(url, json={}, headers=headers)
            if response.status_code != 200:
                with lock:
                    failures.append(response.status_code)
                return
            got = harvest(response.json())
            if got is not None:
                with lock:
                    received.append(got)
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
    assert failures == []
    return received


def otpk_of(body):
    bundle = body["bundles"][0]
    return bundle["otpk"]["key_id"] if "otpk" in bundle else None


def test_one_prekey_is_handed_to_at_most_one_concurrent_claimant(
    new_http, active_user, device, bearer, peer, owner_device
):
    stock_prekeys(owner_device, 1, start=99)

    received = storm(
        new_http,
        f"/api/v1/users/{peer.id}/keys/claim",
        bearer(active_user, device),
        otpk_of,
    )

    assert received == [99], f"the single OTPK went to {len(received)} claimants"
    assert OneTimePrekey.objects.filter(device=owner_device).count() == 0


def test_a_pool_is_never_handed_out_twice_over(
    new_http, active_user, device, bearer, peer, owner_device
):
    """Several keys, more claimants than keys: every key goes out exactly once."""
    pool = 5
    stock_prekeys(owner_device, pool, start=200)

    received = storm(
        new_http,
        f"/api/v1/users/{peer.id}/keys/claim",
        bearer(active_user, device),
        otpk_of,
    )

    assert sorted(received) == list(range(200, 200 + pool))
    assert len(received) == len(set(received))  # no key twice
    assert OneTimePrekey.objects.filter(device=owner_device).count() == 0


def test_the_race_is_real_without_skip_locked(owner_device):
    """Guards the guard. Read-then-delete over the same row, under the same load,
    double-spends, so the assertions above are not passing vacuously because the
    threads never actually overlapped."""
    stock_prekeys(owner_device, 1, start=1)
    start = threading.Barrier(CONCURRENT_CLAIMS)
    winners = []
    lock = threading.Lock()

    def naive_claim():
        try:
            connect_then_wait(start)
            with transaction.atomic():
                row = (
                    OneTimePrekey.objects.filter(device_id=owner_device.id)
                    .order_by("key_id")
                    .first()
                )  # no select_for_update
                if row is None:
                    return
                OneTimePrekey.objects.filter(pk=row.pk).delete()
                with lock:
                    winners.append(row.key_id)
        finally:
            connections.close_all()

    threads = [threading.Thread(target=naive_claim) for _ in range(CONCURRENT_CLAIMS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)

    assert len(winners) > 1, (
        "the unguarded read-then-delete did NOT double-spend, so these threads are "
        "not really contending and the single-consumption assertions prove nothing"
    )
