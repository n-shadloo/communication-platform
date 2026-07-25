"""The device cap holds under concurrent registration.

`TransactionTestCase` for the same reason as the claim race: the guard is a row lock
held to commit, which a wrapping test transaction would hide.
"""
import threading

from django.core.cache import cache
from django.db import connections, transaction
from django.test import TransactionTestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_register_scope
from devices.models import Device

from .conftest import DEVICES_URL, PASSWORD, make_device, register_payload

CONCURRENT_REGISTRATIONS = 4


class DeviceLimitRaceTests(TransactionTestCase):

    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(username="collector", password=PASSWORD,
                                             is_active=True)
        from .conftest import publish_identity
        publish_identity(self.user)  # registration past the first device needs one

    def _fill_to(self, live_devices):
        for i in range(live_devices):
            make_device(self.user, registration_id=300 + i)

    def test_concurrent_registrations_cannot_exceed_the_cap(self):
        cap = 10  # settings.MAX_DEVICES_PER_USER
        self._fill_to(cap - 1)  # one slot left
        start = threading.Barrier(CONCURRENT_REGISTRATIONS)
        statuses = []
        lock = threading.Lock()

        def register():
            try:
                start.wait(timeout=10)
                headers = {"HTTP_AUTHORIZATION":
                           f"Bearer {issue_register_scope(self.user)}"}
                response = APIClient().post(DEVICES_URL, register_payload(),
                                            format="json", **headers)
                with lock:
                    statuses.append(response.status_code)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=register)
                   for _ in range(CONCURRENT_REGISTRATIONS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        live = Device.objects.filter(user=self.user, revoked_date__isnull=True).count()
        self.assertLessEqual(live, cap, f"cap breached: {live} live devices")
        self.assertEqual(statuses.count(201), 1)
        self.assertEqual(statuses.count(409), CONCURRENT_REGISTRATIONS - 1)

    def test_locking_the_device_rows_would_not_have_held(self):
        """Guards the guard. The obvious implementation, `select_for_update()` over
        the account's existing devices, does not stop a concurrent INSERT, and Django
        silently drops FOR UPDATE altogether when the queryset ends in `.count()`.
        Under this same load it lets the account past the cap, which is why the view
        locks the user row instead."""
        cap = 10
        self._fill_to(cap - 1)
        start = threading.Barrier(CONCURRENT_REGISTRATIONS)

        def naive_register():
            try:
                start.wait(timeout=10)
                with transaction.atomic():
                    n = Device.objects.select_for_update().filter(
                        user_id=self.user.id, revoked_date__isnull=True).count()
                    if n >= cap:
                        return
                    make_device(self.user, registration_id=999)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=naive_register)
                   for _ in range(CONCURRENT_REGISTRATIONS)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        live = Device.objects.filter(user=self.user, revoked_date__isnull=True).count()
        self.assertGreater(live, cap,
                           "the device-row lock held after all, so the user-row lock "
                           "in the view is not what is keeping the cap")
