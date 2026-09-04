"""Nothing on the device or key-distribution paths logs an identifier or key material.

`assertLogs` swaps in its own root handler, so the configured `ScrubFilter` is not
applied to what it captures. That is deliberate: these tests assert the code never
emits an identifier in the first place; `core/tests/test_scrub.py` covers the filter.
"""

import logging

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from api.auth import issue_full, issue_register_scope

from .conftest import (
    DEVICES_URL,
    PASSWORD,
    label_blob,
    make_device,
    pubkey,
    register_payload,
    stock_prekeys,
)


class DeviceLogSilenceTests(TestCase):
    def setUp(self):
        self.alice = User.objects.create_user(
            username="alice", password=PASSWORD, is_active=True
        )
        from .conftest import publish_identity

        publish_identity(self.alice)  # registration past the first device needs one
        self.device = make_device(self.alice, 1)
        self.peer = User.objects.create_user(
            username="peer", password=PASSWORD, is_active=True
        )
        self.peer_device = make_device(self.peer, 2)
        stock_prekeys(self.peer_device, 2)
        access, _refresh = issue_full(self.alice, self.device)
        self.headers = {"HTTP_AUTHORIZATION": f"Bearer {access}"}
        self.client = APIClient()

    def test_the_whole_device_lifecycle_emits_no_identifier_or_key(self):
        payload = register_payload(otpks=2, label_blob=label_blob())

        with self.assertLogs(level="DEBUG") as captured:
            # assertLogs fails outright if nothing is logged, and a clean request logs
            # nothing at all — which is the point. The canary keeps it honest.
            logging.getLogger("test.canary").debug("canary")

            registered = self.client.post(
                DEVICES_URL, payload, format="json", **self.headers
            )
            new_id = registered.json()["device_id"]
            self.client.get(DEVICES_URL, **self.headers)
            self.client.get(f"/api/v1/users/{self.peer.id}/devices", **self.headers)
            claim = self.client.post(
                f"/api/v1/users/{self.peer.id}/keys/claim",
                {},
                format="json",
                **self.headers,
            )
            self.client.put(
                f"{DEVICES_URL}/{self.device.id}/prekeys",
                {"otpks": [{"key_id": 42, "pub": pubkey(b"r")}]},
                format="json",
                **self.headers,
            )
            self.client.delete(f"{DEVICES_URL}/{new_id}", **self.headers)

        self.assertEqual(registered.status_code, 201)
        bundle = claim.json()["bundles"][0]
        forbidden = {
            "registered device id": new_id,
            "calling device id": str(self.device.id),
            "peer device id": str(self.peer_device.id),
            "caller user id": str(self.alice.id),
            "peer user id": str(self.peer.id),
            "uploaded identity key": payload["ik_pub"],
            "uploaded label blob": payload["label_blob"],
            "claimed identity key": bundle["ik_pub"],
            "claimed one-time prekey": bundle["otpk"]["pub"],
            "issued access token": registered.json()["access"],
            "issued refresh token": registered.json()["refresh"],
        }
        for line in captured.output:
            for label, secret in forbidden.items():
                self.assertNotIn(secret, line, f"{label} leaked into a log line")

    def test_rejected_input_is_not_echoed_into_the_logs(self):
        """The bad-bucket and forbidden paths must not log what they refused."""
        import base64

        off_bucket = base64.b64encode(b"q" * 77).decode()

        with self.assertLogs(level="DEBUG") as captured:
            logging.getLogger("test.canary").debug("canary")
            rejected = self.client.post(
                DEVICES_URL,
                register_payload(label_blob=off_bucket),
                format="json",
                **self.headers,
            )
            forbidden = self.client.get(
                f"{DEVICES_URL}/{self.peer_device.id}/prekeys/count", **self.headers
            )
            scoped_out = self.client.get(
                DEVICES_URL,
                HTTP_AUTHORIZATION=f"Bearer {issue_register_scope(self.alice)}",
            )

        self.assertEqual(rejected.status_code, 400)
        self.assertEqual(forbidden.status_code, 403)
        self.assertEqual(scoped_out.status_code, 403)
        for line in captured.output:
            self.assertNotIn(off_bucket, line)
            self.assertNotIn(str(self.peer_device.id), line)
            self.assertNotIn(str(self.alice.id), line)
