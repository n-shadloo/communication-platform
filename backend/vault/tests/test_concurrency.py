"""Same-owner history appends assign `seq` atomically under the owner-row lock.

`TransactionTestCase` because the guarantee rests on a real committed row lock racing
other transactions, which a wrapping test transaction would hide (mirrors messaging's
per-device seq test).
"""
import base64
import threading

from django.core.cache import cache
from django.db import connections
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full
from vault.models import HistoryRecord, KeyBackup

from .conftest import PASSWORD, backup_blob, history_blob, make_device

CONCURRENT_APPENDS = 12
RACE_ROUNDS = 20


class SameOwnerAppendConcurrencyTests(TransactionTestCase):

    def setUp(self):
        self.owner = User.objects.create_user(username="alice", password=PASSWORD,
                                               is_active=True)
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
                    "/api/v1/me/history",
                    {"records": [{"blob": history_blob()}]},
                    format="json", **self.headers)
                if resp.status_code != 201:
                    failures.append(resp.status_code)
            except Exception as exc:  # a seq collision surfaces as IntegrityError → 500
                failures.append(repr(exc))
            finally:
                connections.close_all()

        threads = [threading.Thread(target=append_one) for _ in range(CONCURRENT_APPENDS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(failures, [])
        seqs = sorted(HistoryRecord.objects.filter(owner_id=self.owner.id)
                      .values_list("seq", flat=True))
        # Unique (no lost update) and gapless (nothing reserved then dropped): the log
        # pages deterministically. History seq starts at 0.
        self.assertEqual(seqs, list(range(CONCURRENT_APPENDS)))

    def test_the_unique_constraint_would_catch_a_duplicate_seq(self):
        """Guards the guard: without the (owner, seq) unique constraint the race test
        above could pass vacuously if the counter logic were ever broken."""
        HistoryRecord.objects.create(owner=self.owner, seq=0, blob=b"a" * 1024)
        with self.assertRaises(Exception):
            HistoryRecord.objects.create(owner=self.owner, seq=0, blob=b"b" * 1024)


class KeyBackupVersionRaceTests(TransactionTestCase):
    """A concurrent first key-backup upload must not let a lower version win.

    The owner-row lock makes this deterministic: whichever write commits first sets
    the version, and the other either sees it and 409s (lower) or applies over it
    (higher), so the stored version is always the maximum. Without the lock both
    writes read version=None and the lower one can clobber the higher."""

    def setUp(self):
        self.owner = User.objects.create_user(username="alice", password=PASSWORD,
                                               is_active=True)
        access_low, _ = issue_full(self.owner, make_device(self.owner, 1))
        access_high, _ = issue_full(self.owner, make_device(self.owner, 2))
        self.low = {"HTTP_AUTHORIZATION": f"Bearer {access_low}"}
        self.high = {"HTTP_AUTHORIZATION": f"Bearer {access_high}"}
        cache.clear()  # a shared throttle cache would otherwise bleed across rounds

    def test_concurrent_first_write_never_lets_the_lower_version_win(self):
        high_blob = backup_blob(b"H")
        expected_high = base64.b64decode(high_blob)
        for _ in range(RACE_ROUNDS):
            KeyBackup.objects.filter(user_id=self.owner.id).delete()  # force a first write
            barrier = threading.Barrier(2)

            def put(headers, version, blob):
                try:
                    barrier.wait(timeout=10)
                    APIClient().put("/api/v1/me/keybackup",
                                    {"blob": blob, "version": version},
                                    format="json", **headers)
                finally:
                    connections.close_all()

            threads = [
                threading.Thread(target=put, args=(self.low, 1, backup_blob(b"L"))),
                threading.Thread(target=put, args=(self.high, 5, high_blob)),
            ]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=30)

            key_backup = KeyBackup.objects.get(user_id=self.owner.id)
            self.assertEqual(key_backup.version, 5)
            self.assertEqual(bytes(key_backup.blob), expected_high)
