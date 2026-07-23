"""Nothing on the messaging or attachment paths logs an identifier or a payload.

`assertLogs` swaps in its own root handler, so the configured `ScrubFilter` is not
applied to what it captures. That is deliberate: these tests assert the code never
emits an identifier in the first place; `core/tests/test_scrub.py` covers the filter.
"""
import base64
import logging
import tempfile
from pathlib import Path

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User
from accounts.tokens import issue_full
from core.buckets import ATTACHMENT_BUCKETS

from .conftest import PASSWORD, SMALLEST_BUCKET, envelope_blob, make_device


@override_settings(CHANNEL_LAYERS={
    "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}})
class LogSilenceTests(TestCase):

    def setUp(self):
        # Uploads must land in a temp dir, never the repo's media_root.
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        attachments_root = override_settings(ATTACHMENTS_ROOT=Path(tmp.name))
        attachments_root.enable()
        self.addCleanup(attachments_root.disable)

        self.alice = User.objects.create_user(username="alice", password=PASSWORD,
                                              is_active=True)
        self.device = make_device(self.alice, 1)
        self.bob = User.objects.create_user(username="bob", password=PASSWORD,
                                            is_active=True)
        self.target = make_device(self.bob, 2)
        access, _refresh = issue_full(self.alice, self.device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.client = APIClient()

    def test_send_drain_ack_and_upload_emit_no_identifier_or_payload(self):
        blob = envelope_blob(b"z")
        upload_bytes = b"\x01" * min(ATTACHMENT_BUCKETS)

        with self.assertLogs(level="DEBUG") as captured:
            # assertLogs fails outright if nothing is logged, and a clean request logs
            # nothing at all — which is the point. The canary keeps it honest.
            logging.getLogger("test.canary").debug("canary")

            send = self.client.post(
                "/api/v1/envelopes",
                {"messages": [{"device_id": str(self.target.id), "blob": blob}]},
                format="json", **self.headers)
            drain = self.client.get("/api/v1/me/envelopes", **self.headers)
            self.client.post("/api/v1/me/envelopes/ack",
                             {"ids": [e["id"] for e in drain.json()["envelopes"]]},
                             format="json", **self.headers)
            upload = self.client.post(
                "/api/v1/attachments",
                {"blob": SimpleUploadedFile("blob", upload_bytes)},
                format="multipart", **self.headers)

        self.assertEqual(send.status_code, 202)
        self.assertEqual(upload.status_code, 201)

        forbidden = {
            "device id": str(self.target.id),
            "sender device id": str(self.device.id),
            "user id": str(self.alice.id),
            "recipient user id": str(self.bob.id),
            "envelope blob": blob,
            "attachment id": upload.json()["attachment_id"],
            "attachment bytes": base64.b64encode(upload_bytes).decode(),
        }
        for line in captured.output:
            for label, secret in forbidden.items():
                self.assertNotIn(secret, line, f"{label} leaked into a log line")

    def test_a_rejected_payload_is_not_echoed_into_the_logs(self):
        off_bucket = base64.b64encode(b"q" * (SMALLEST_BUCKET - 1)).decode()

        with self.assertLogs(level="DEBUG") as captured:
            logging.getLogger("test.canary").debug("canary")
            resp = self.client.post(
                "/api/v1/envelopes",
                {"messages": [{"device_id": str(self.target.id), "blob": off_bucket}]},
                format="json", **self.headers)

        self.assertEqual(resp.status_code, 400)
        for line in captured.output:
            self.assertNotIn(off_bucket, line)
            self.assertNotIn(str(self.target.id), line)
