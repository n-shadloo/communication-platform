"""Log-silence audit (§A11.4): one scripted pass over every traffic surface — auth,
devices, messaging, attachments, realtime, voice — captured at DEBUG, then scanned for
every identifier, blob, and token the pass generated. Returns a list of leaks; the
system is honest only when it is empty.

Two properties make this stricter than per-app spot checks:

- The capture bypasses the ScrubFilter. The filter mutates records in place, so any
  capture attached after the console handler grades the scrubber, not the code
  (the Phase-6 lesson). The scrubber is a backstop; the primary control — audited here —
  is that nothing is ever logged in the first place.
- The capture swaps the handlers of the root logger AND of every named logger that has
  its own (django.request/django.server/daphne set propagate=False, so a root-only swap
  — what assertLogs does — never sees them).

Driven by core/tests/test_log_silence.py; needs the test DB, the in-memory channel
layer, a temp ATTACHMENTS_ROOT, and fake LIVEKIT_* settings (token minting is local
PyJWT — no network is ever touched).
"""
import base64
import logging
import secrets as random_secrets
from contextlib import contextmanager

CANARY = "log-silence-audit-canary"


class _RawCapture(logging.Handler):
    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.lines = []

    def emit(self, record):
        self.lines.append(f"{record.levelname} {record.name} {record.getMessage()}")


@contextmanager
def capture_all_logging():
    """Route every logger that owns handlers (plus root) into one raw capture list,
    at DEBUG, with the configured handlers — and therefore the ScrubFilter — bypassed."""
    handler = _RawCapture()
    root = logging.getLogger()
    named = [logging.getLogger(name) for name in list(logging.root.manager.loggerDict)]
    targets = [root] + [lg for lg in named
                        if isinstance(lg, logging.Logger) and lg.handlers]
    saved = [(lg, lg.handlers[:], lg.level) for lg in targets]
    for lg in targets:
        lg.handlers[:] = [handler]
        lg.setLevel(logging.DEBUG)
    try:
        yield handler.lines
    finally:
        for lg, handlers, level in saved:
            lg.handlers[:] = handlers
            lg.setLevel(level)


def _b64_filled(size, fill):
    return base64.b64encode(bytes([fill]) * size).decode()


def _scripted_rest_traffic():
    """The REST half of the sequence. Returns {label: generated secret} — everything a
    log line must never contain. Runs in a worker thread via database_sync_to_async;
    logging is process-global, so the capture still sees every record."""
    from django.core.cache import cache
    from django.core.files.uploadedfile import SimpleUploadedFile
    from rest_framework.test import APIClient

    from accounts.models import User
    from core.buckets import (ATTACHMENT_BUCKETS, ENVELOPE_BUCKETS, KEYPACKAGE_BUCKETS,
                              NAME_BUCKETS)

    api = APIClient()
    cache.clear()  # DRF throttle counters live in the shared cache
    s = {"username": f"aud{random_secrets.token_hex(6)}",
         "password": random_secrets.token_urlsafe(24)}

    # Register, then activate — activation is the owner's admin action (§7); its
    # server-side effect is the is_active flip.
    r = api.post("/api/v1/auth/register",
                 {"username": s["username"], "password": s["password"]}, format="json")
    assert r.status_code == 201, f"register: {r.status_code}"
    s["user id"] = r.json()["user_id"]
    User.objects.filter(id=s["user id"]).update(is_active=True)

    # Login with no device: the register-scope token whose only power is POST /me/devices.
    r = api.post("/api/v1/auth/login",
                 {"username": s["username"], "password": s["password"]}, format="json")
    assert r.status_code == 200, f"login: {r.status_code}"
    s["register-scope access token"] = r.json()["access"]

    r = api.post(
        "/api/v1/me/devices",
        {"ik_pub": _b64_filled(32, 0x69), "spk_id": 1, "spk_pub": _b64_filled(32, 0x73),
         "spk_sig": _b64_filled(32, 0x67), "registration_id": 4242,
         "otpks": [{"key_id": 1, "pub": _b64_filled(32, 0x6F)}],
         "keypackages": [_b64_filled(min(KEYPACKAGE_BUCKETS), 0x6B)]},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {s['register-scope access token']}")
    assert r.status_code == 201, f"device register: {r.status_code}"
    body = r.json()
    s["device id"] = body["device_id"]
    s["access token"] = body["access"]
    s["refresh token"] = body["refresh"]
    auth = {"HTTP_AUTHORIZATION": f"Bearer {s['access token']}"}

    # Send an envelope to our own device (self-sync shape), drain it, ack it.
    s["envelope blob"] = _b64_filled(min(ENVELOPE_BUCKETS), 0xA5)
    r = api.post("/api/v1/envelopes",
                 {"messages": [{"device_id": s["device id"], "blob": s["envelope blob"]}]},
                 format="json", **auth)
    assert r.status_code == 202, f"send: {r.status_code}"
    r = api.get("/api/v1/me/envelopes", **auth)
    assert r.status_code == 200 and r.json()["envelopes"], "drain returned nothing"
    envelopes = r.json()["envelopes"]
    s["queued envelope id"] = envelopes[0]["id"]
    r = api.post("/api/v1/me/envelopes/ack",
                 {"ids": [e["id"] for e in envelopes]}, format="json", **auth)
    assert r.status_code == 200, f"ack: {r.status_code}"

    # Upload + download an attachment (download answers via X-Accel-Redirect).
    upload_bytes = b"\x01" * min(ATTACHMENT_BUCKETS)
    r = api.post("/api/v1/attachments",
                 {"blob": SimpleUploadedFile("blob", upload_bytes)},
                 format="multipart", **auth)
    assert r.status_code == 201, f"upload: {r.status_code}"
    s["attachment id"] = r.json()["attachment_id"]
    r = api.get(f"/api/v1/attachments/{s['attachment id']}", **auth)
    assert r.status_code == 200, f"download: {r.status_code}"

    # Create a room and mint a LiveKit join token (local HS256 signing, §A9).
    s["room name blob"] = _b64_filled(min(NAME_BUCKETS), 0xB6)
    r = api.post("/api/v1/rooms", {"name_blob": s["room name blob"]},
                 format="json", **auth)
    assert r.status_code == 201, f"room create: {r.status_code}"
    s["room id"] = r.json()["room_id"]
    r = api.post(f"/api/v1/rooms/{s['room id']}/token", **auth)
    assert r.status_code == 200, f"room token: {r.status_code}"
    s["livekit join token"] = r.json()["token"]
    return s


async def _scripted_socket_traffic(s):
    """The realtime half: authenticated connect, a volatile signal round-trip to our own
    device, disconnect. Adds the signal blob to the secret set."""
    from channels.testing import WebsocketCommunicator

    from config.asgi import application

    comm = WebsocketCommunicator(
        application, "/ws",
        headers=[(b"authorization", f"Bearer {s['access token']}".encode())])
    connected, _ = await comm.connect(timeout=2)
    assert connected, "socket handshake refused"
    s["signal blob"] = f"volatile-{random_secrets.token_hex(12)}"
    await comm.send_json_to({"type": "signal", "to_device": s["device id"],
                             "blob": s["signal blob"]})
    frame = await comm.receive_json_from(timeout=2)
    assert frame == {"type": "signal", "blob": s["signal blob"]}, "signal did not relay"
    await comm.disconnect()


def scan(lines, secrets):
    """Every captured line vs every generated secret. Substring match: an id inside a
    traceback, a repr, or a formatted message is still a leak."""
    return [f"{label} leaked into: {line[:160]}"
            for line in lines
            for label, secret in secrets.items()
            if secret and str(secret) in line]


async def run_audit(probe=None):
    """Run the scripted sequence under full capture. Returns (leaks, secrets, lines).

    `probe(secrets)` — test hook, called inside the capture window after the scripted
    traffic — lets the suite prove the audit still catches a deliberate leak."""
    from channels.db import database_sync_to_async

    with capture_all_logging() as lines:
        logging.getLogger("ops.audit.canary").debug(CANARY)
        secrets = await database_sync_to_async(_scripted_rest_traffic)()
        await _scripted_socket_traffic(secrets)
        if probe is not None:
            probe(secrets)
    if not any(CANARY in line for line in lines):
        raise RuntimeError("log capture was not live; this audit proved nothing")
    return scan(lines, secrets), secrets, lines
