"""No vault endpoint logs an identifier or a payload (§A11.4, audit a09).

`assertLogs` installs its own handler, so the configured ScrubFilter is not applied here
— that is the point: this asserts the code never emits an id or blob in the first place.
"""
import logging

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full

from .conftest import PASSWORD, backup_blob, history_blob, make_device


class VaultLogSilenceTests(TestCase):

    def setUp(self):
        self.owner = User.objects.create_user(username="alice", password=PASSWORD,
                                               is_active=True)
        self.device = make_device(self.owner, 1)
        access, _refresh = issue_full(self.owner, self.device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.client = APIClient()

    def test_backup_and_history_paths_emit_no_identifier_or_blob(self):
        kb = backup_blob(b"S")
        hb = history_blob(b"z")

        with self.assertLogs(level="DEBUG") as captured:
            # assertLogs fails if nothing is logged; a clean request logs nothing at all,
            # so the canary keeps the block honest.
            logging.getLogger("test.canary").debug("canary")

            put = self.client.put("/api/v1/me/keybackup", {"blob": kb, "version": 1},
                                  format="json", **self.headers)
            post = self.client.post("/api/v1/me/history", {"records": [{"blob": hb}]},
                                    format="json", **self.headers)
            self.client.get("/api/v1/me/history?after=-1&limit=100", **self.headers)
            self.client.get("/api/v1/me/history/usage", **self.headers)
            self.client.post("/api/v1/me/history/delete", {"all": True},
                             format="json", **self.headers)

        self.assertEqual(put.status_code, 200)
        self.assertEqual(post.status_code, 201)

        forbidden = {
            "owner id": str(self.owner.id),
            "device id": str(self.device.id),
            "backup blob": kb,
            "history blob": hb,
        }
        for line in captured.output:
            for label, secret in forbidden.items():
                self.assertNotIn(secret, line, f"{label} leaked into a log line")
