"""Single consumption under concurrency.

`TransactionTestCase` because the point is real committed transactions racing: the
claim relies on `SELECT ... LIMIT 1 FOR UPDATE SKIP LOCKED` plus a delete inside the
same transaction, and a wrapping test transaction would hide exactly that.
"""
import threading

from django.core.cache import cache
from django.db import connections, transaction
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full
from devices.models import KeyPackage, OneTimePrekey

from .conftest import PASSWORD, make_device, stock_keypackages, stock_prekeys

CONCURRENT_CLAIMS = 12


class ClaimRaceTests(TransactionTestCase):

    def setUp(self):
        cache.clear()  # DRF throttle counters are shared across the run
        self.claimant = User.objects.create_user(username="claimant", password=PASSWORD,
                                                 is_active=True)
        self.claimant_device = make_device(self.claimant, registration_id=1)
        self.owner = User.objects.create_user(username="owner", password=PASSWORD,
                                              is_active=True)
        self.owner_device = make_device(self.owner, registration_id=2)
        access, _refresh = issue_full(self.claimant, self.claimant_device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def _storm(self, url, harvest):
        """Fire CONCURRENT_CLAIMS requests at once and collect what each got."""
        start = threading.Barrier(CONCURRENT_CLAIMS)
        received, failures = [], []
        lock = threading.Lock()

        def claim():
            try:
                start.wait(timeout=10)
                response = APIClient().post(url, {}, format="json", **self.headers)
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
        self.assertEqual(failures, [])
        return received

    @staticmethod
    def _otpk_of(body):
        bundle = body["bundles"][0]
        return bundle["otpk"]["key_id"] if "otpk" in bundle else None

    @staticmethod
    def _keypackage_of(body):
        packages = body["keypackages"]
        return packages[0]["blob"] if packages else None

    def test_one_prekey_is_handed_to_at_most_one_concurrent_claimant(self):
        stock_prekeys(self.owner_device, 1, start=99)

        received = self._storm(f"/api/v1/users/{self.owner.id}/keys/claim",
                               self._otpk_of)

        self.assertEqual(received, [99],
                         f"the single OTPK went to {len(received)} claimants")
        self.assertEqual(
            OneTimePrekey.objects.filter(device=self.owner_device).count(), 0)

    def test_a_pool_is_never_handed_out_twice_over(self):
        """Several keys, more claimants than keys: every key goes out exactly once."""
        pool = 5
        stock_prekeys(self.owner_device, pool, start=200)

        received = self._storm(f"/api/v1/users/{self.owner.id}/keys/claim",
                               self._otpk_of)

        self.assertEqual(sorted(received), list(range(200, 200 + pool)))
        self.assertEqual(len(received), len(set(received)))  # no key twice
        self.assertEqual(
            OneTimePrekey.objects.filter(device=self.owner_device).count(), 0)

    def test_one_key_package_is_handed_to_at_most_one_concurrent_claimant(self):
        stock_keypackages(self.owner_device, 1)

        received = self._storm(f"/api/v1/users/{self.owner.id}/keypackages/claim",
                               self._keypackage_of)

        self.assertEqual(len(received), 1,
                         f"the single key package went to {len(received)} claimants")
        self.assertEqual(KeyPackage.objects.filter(device=self.owner_device).count(), 0)

    def test_the_race_is_real_without_skip_locked(self):
        """Guards the guard. Read-then-delete over the same row, under the same load,
        double-spends, so the assertions above are not passing vacuously because the
        threads never actually overlapped."""
        stock_prekeys(self.owner_device, 1, start=1)
        start = threading.Barrier(CONCURRENT_CLAIMS)
        winners = []
        lock = threading.Lock()

        def naive_claim():
            try:
                start.wait(timeout=10)
                with transaction.atomic():
                    row = (OneTimePrekey.objects
                           .filter(device_id=self.owner_device.id)
                           .order_by("key_id").first())  # no select_for_update
                    if row is None:
                        return
                    OneTimePrekey.objects.filter(pk=row.pk).delete()
                    with lock:
                        winners.append(row.key_id)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=naive_claim)
                   for _ in range(CONCURRENT_CLAIMS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertGreater(len(winners), 1,
                           "the unguarded read-then-delete did NOT double-spend, so "
                           "these threads are not really contending and the "
                           "single-consumption assertions prove nothing")
