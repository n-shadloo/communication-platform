"""No vault endpoint logs an identifier or a payload.

`assertLogs` installs its own handler, so the configured ScrubFilter is not applied
here. That is the point: this asserts the code never emits an id or blob in the
first place.
"""
import logging

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full

from .conftest import PASSWORD, backup_blob, make_device


class VaultLogSilenceTests(TestCase):

    def setUp(self):
        self.owner = User.objects.create_user(username="alice", password=PASSWORD,
                                               is_active=True)
        self.device = make_device(self.owner, 1)
        access, _refresh = issue_full(self.owner, self.device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.client = APIClient()

    def test_backup_paths_emit_no_identifier_or_blob(self):
        backup_payload = backup_blob(b"S")

        with self.assertLogs(level="DEBUG") as captured:
            # assertLogs fails if nothing is logged; a clean request logs nothing at all,
            # so the canary keeps the block honest.
            logging.getLogger("test.canary").debug("canary")

            put = self.client.put("/api/v1/me/keybackup",
                                  {"blob": backup_payload, "version": 1},
                                  format="json", **self.headers)
            get = self.client.get("/api/v1/me/keybackup", **self.headers)

        self.assertEqual(put.status_code, 200)
        self.assertEqual(get.status_code, 200)

        forbidden = {
            "owner id": str(self.owner.id),
            "device id": str(self.device.id),
            "backup blob": backup_payload,
        }
        for line in captured.output:
            for label, secret in forbidden.items():
                self.assertNotIn(secret, line, f"{label} leaked into a log line")
