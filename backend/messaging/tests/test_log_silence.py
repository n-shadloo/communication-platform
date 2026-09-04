"""Nothing on the messaging or attachment paths logs an identifier or a payload.

The capture replaces every handler, so the configured `ScrubFilter` never runs on
what it collects. That is deliberate, and it is why `caplog` is not used here: the
filter mutates the record in place on the console handler, so any capture that
runs after it grades the scrubber rather than the code. `core/tests/test_scrub.py`
covers the filter itself.

The upload rides along because it is the one body of this API that is bytes rather
than JSON: a multipart part and a capability id are two more shapes that must never
reach a log line.
"""

import base64
import logging

import pytest

from core.buckets import ATTACHMENT_BUCKETS
from ops.audit.log_silence import capture_all_logging

from .conftest import SMALLEST_BUCKET, envelope_blob, make_device

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture(autouse=True)
def _uploads_out_of_the_repository(settings, tmp_path):
    settings.ATTACHMENTS_ROOT = tmp_path


def test_send_drain_ack_and_upload_emit_no_identifier_or_payload(
    http, active_user, device, bearer, bob, bob_devices
):
    target = bob_devices[0]
    blob = envelope_blob(b"z")
    headers = bearer(active_user, device)
    upload_bytes = b"\x01" * min(ATTACHMENT_BUCKETS)

    with capture_all_logging() as lines:
        send = http.post(
            "/api/v1/envelopes",
            json={"messages": [{"device_id": str(target.id), "blob": blob}]},
            headers=headers,
        )
        drain = http.get("/api/v1/me/envelopes", headers=bearer(bob, target))
        http.post(
            "/api/v1/me/envelopes/ack",
            json={"ids": [e["id"] for e in drain.json()["envelopes"]]},
            headers=bearer(bob, target),
        )
        upload = http.post(
            "/api/v1/attachments",
            files={"blob": ("blob", upload_bytes)},
            headers=headers,
        )

    assert send.status_code == 202
    assert upload.status_code == 201
    forbidden = {
        "device id": str(target.id),
        "sender device id": str(device.id),
        "user id": str(active_user.id),
        "recipient user id": str(bob.id),
        "envelope blob": blob,
        "attachment id": upload.json()["attachment_id"],
        "attachment bytes": base64.b64encode(upload_bytes).decode(),
    }
    for line in lines:
        for label, secret in forbidden.items():
            assert secret not in line, f"{label} leaked into a log line"


def test_a_rejected_payload_is_not_echoed_into_the_logs(
    http, active_user, device, bearer, bob_devices
):
    target = bob_devices[0]
    off_bucket = base64.b64encode(b"q" * (SMALLEST_BUCKET - 1)).decode()

    with capture_all_logging() as lines:
        resp = http.post(
            "/api/v1/envelopes",
            json={"messages": [{"device_id": str(target.id), "blob": off_bucket}]},
            headers=bearer(active_user, device),
        )

    assert resp.status_code == 400
    for line in lines:
        assert off_bucket not in line
        assert str(target.id) not in line


def test_the_capture_is_live_and_unscrubbed(bob):
    """Guards the guards above. A clean request logs nothing at all, so a loop over
    an empty list would pass no matter what the code emitted; and a capture that
    ran behind the console handler would read `[ID]` where the leak was, and pass
    for the second wrong reason."""
    planted = make_device(bob, 77)

    with capture_all_logging() as lines:
        logging.getLogger("messaging.tests.canary").debug("device %s", planted.id)

    assert any(str(planted.id) in line for line in lines)
