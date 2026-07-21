"""Per-device `seq` assignment is atomic under concurrency (§A4).

`TransactionTestCase` because the point is real committed transactions racing each other:
the enqueue relies on the row lock that `UPDATE ... SET queue_seq = queue_seq + 1` holds
until commit, which a wrapping test transaction would hide.
"""
import threading

from django.db import connections
from django.test import TransactionTestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full
from devices.models import Device
from messaging.models import QueuedEnvelope

from .conftest import PASSWORD, envelope_blob, make_device

CONCURRENT_SENDS = 12


@override_settings(CHANNEL_LAYERS={
    "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}})
class PerDeviceSeqConcurrencyTests(TransactionTestCase):

    def setUp(self):
        self.sender = User.objects.create_user(username="alice", password=PASSWORD,
                                               is_active=True)
        self.sender_device = make_device(self.sender, 1)
        recipient = User.objects.create_user(username="bob", password=PASSWORD,
                                             is_active=True)
        self.target = make_device(recipient, 2)
        access, _refresh = issue_full(self.sender, self.sender_device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}

    def test_concurrent_sends_to_one_device_never_collide_or_gap(self):
        failures = []
        # A barrier so the workers contend on the same row instead of trickling through.
        start = threading.Barrier(CONCURRENT_SENDS)

        def send():
            try:
                start.wait(timeout=10)
                resp = APIClient().post(
                    "/api/v1/envelopes",
                    {"messages": [{"device_id": str(self.target.id),
                                   "blob": envelope_blob()}]},
                    format="json", **self.headers)
                if resp.status_code != 202:
                    failures.append(resp.status_code)
            except Exception as exc:  # a seq collision surfaces as IntegrityError → 500
                failures.append(repr(exc))
            finally:
                connections.close_all()

        threads = [threading.Thread(target=send) for _ in range(CONCURRENT_SENDS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(failures, [])
        seqs = sorted(QueuedEnvelope.objects
                      .filter(recipient_device_id=self.target.id)
                      .values_list("seq", flat=True))
        # Unique (no lost update) and gapless (nothing reserved then dropped), so the
        # mailbox orders deterministically.
        self.assertEqual(seqs, list(range(1, CONCURRENT_SENDS + 1)))
        self.assertEqual(
            Device.objects.get(id=self.target.id).queue_seq, CONCURRENT_SENDS)

    def test_the_unique_constraint_would_catch_a_duplicate_seq(self):
        """Guards the guard: without this, the test above could pass vacuously if the
        constraint were ever dropped."""
        QueuedEnvelope.objects.create(recipient_device=self.target, seq=1,
                                      blob=b"a" * 1024)

        with self.assertRaises(Exception):
            QueuedEnvelope.objects.create(recipient_device=self.target, seq=1,
                                          blob=b"b" * 1024)
