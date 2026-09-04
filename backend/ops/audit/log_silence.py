"""Log-silence audit: one scripted pass over every traffic surface (auth, devices,
messaging, attachments, realtime, voice), captured at DEBUG, then scanned for every
identifier, blob, and token the pass generated. Returns a list of leaks; the system
is honest only when it is empty.

Two properties make this stricter than per-app spot checks:

- The capture bypasses the ScrubFilter. The filter mutates records in place, so any
  capture attached after the console handler grades the scrubber, not the code. The
  scrubber is a backstop; the primary control, audited here, is that nothing is ever
  logged in the first place.
- The capture swaps the handlers of the root logger and of every named logger that
  has its own (django.request/django.server/daphne set propagate=False, so a
  root-only swap, which is what assertLogs does, never sees them).

Two clients drive the pass, because two runtimes serve it: an httpx client over the
composed ASGI application for the routes FastAPI holds, and the REST Framework
client for the apps that have not moved. The httpx client logs the URL of every
request it makes, which is a request path in a log line — the suite's `conftest.py`
disables that logger, because the client is this harness and not the server.

Driven by core/tests/test_log_silence.py; needs the test DB, the in-memory channel
layer, a temp ATTACHMENTS_ROOT, and fake LIVEKIT_* settings (token minting is local
PyJWT; no network is ever touched).
"""

import base64
import logging
import secrets as random_secrets
from contextlib import contextmanager

CANARY_OPEN = "log-silence-audit-canary-open"
CANARY_CLOSE = "log-silence-audit-canary-close"


class _RawCapture(logging.Handler):
    def __init__(self):
        super().__init__(level=logging.DEBUG)
        self.lines = []

    def emit(self, record):
        self.lines.append(f"{record.levelname} {record.name} {record.getMessage()}")


@contextmanager
def capture_all_logging():
    """Route every logger that owns handlers (plus root) into one raw capture list,
    at DEBUG, with the configured handlers, and therefore the ScrubFilter, bypassed."""
    handler = _RawCapture()
    root = logging.getLogger()
    named = [logging.getLogger(name) for name in list(logging.root.manager.loggerDict)]
    targets = [root] + [
        lg for lg in named if isinstance(lg, logging.Logger) and lg.handlers
    ]
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


def _activate(user_id):
    from accounts.models import User

    User.objects.filter(id=user_id).update(is_active=True)


async def _scripted_account_traffic(client):
    """The account half: register, activate, log in. Returns {label: generated
    secret}, everything a log line must never contain."""
    from channels.db import database_sync_to_async
    from django.core.cache import cache

    await database_sync_to_async(cache.clear)()  # rate counters are shared
    s = {
        "username": f"aud{random_secrets.token_hex(6)}",
        "password": random_secrets.token_urlsafe(24),
    }

    # Register, then activate. Activation is the owner's admin action; its
    # server-side effect is the is_active flip.
    r = await client.post(
        "/api/v1/auth/register",
        json={"username": s["username"], "password": s["password"]},
    )
    assert r.status_code == 201, f"register: {r.status_code}"
    s["user id"] = r.json()["user_id"]
    await database_sync_to_async(_activate)(s["user id"])

    # Login with no device: the register-scope token whose only power is
    # POST /me/devices.
    r = await client.post(
        "/api/v1/auth/login",
        json={"username": s["username"], "password": s["password"]},
    )
    assert r.status_code == 200, f"login: {r.status_code}"
    s["register-scope access token"] = r.json()["access"]
    return s


async def _scripted_envelope_traffic(client, s):
    """The mailbox half: send an envelope to our own device (self-sync shape),
    drain it, ack it."""
    from core.buckets import ENVELOPE_BUCKETS

    auth = {"Authorization": f"Bearer {s['access token']}"}
    s["envelope blob"] = _b64_filled(min(ENVELOPE_BUCKETS), 0xA5)
    r = await client.post(
        "/api/v1/envelopes",
        json={"messages": [{"device_id": s["device id"], "blob": s["envelope blob"]}]},
        headers=auth,
    )
    assert r.status_code == 202, f"send: {r.status_code}"
    r = await client.get("/api/v1/me/envelopes", headers=auth)
    assert r.status_code == 200 and r.json()["envelopes"], "drain returned nothing"
    envelopes = r.json()["envelopes"]
    s["queued envelope id"] = envelopes[0]["id"]
    r = await client.post(
        "/api/v1/me/envelopes/ack",
        json={"ids": [e["id"] for e in envelopes]},
        headers=auth,
    )
    assert r.status_code == 200, f"ack: {r.status_code}"
    return s


def _scripted_rest_traffic(s):
    """The REST Framework half of the sequence, for the apps that have not moved.
    Runs in a worker thread via database_sync_to_async; logging is process-global,
    so the capture still sees every record."""
    from django.core.files.uploadedfile import SimpleUploadedFile
    from rest_framework.test import APIClient

    from core.buckets import ATTACHMENT_BUCKETS, DEVICELOG_BUCKETS, NAME_BUCKETS

    api = APIClient()

    # No cross_sig here: the bundle it signs covers the device_id this call assigns,
    # so registration refuses the field. It goes to the prekeys endpoint below, which
    # is where a real client cross-signs — and where this audit must therefore prove
    # a cross signature never reaches a log line.
    r = api.post(
        "/api/v1/me/devices",
        {
            "ik_pub": _b64_filled(64, 0x69),
            "spk_id": 1,
            "spk_pub": _b64_filled(32, 0x73),
            "spk_sig": _b64_filled(32, 0x67),
            "registration_id": 4242,
            "otpks": [{"key_id": 1, "pub": _b64_filled(32, 0x6F)}],
        },
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {s['register-scope access token']}",
    )
    assert r.status_code == 201, f"device register: {r.status_code}"
    body = r.json()
    s["device id"] = body["device_id"]
    s["access token"] = body["access"]
    s["refresh token"] = body["refresh"]
    auth = {"HTTP_AUTHORIZATION": f"Bearer {s['access token']}"}

    # Cross-sign the device now that its device_id is known (CLIENT_CONTRACT.md §M).
    s["cross signature"] = _b64_filled(64, 0x78)
    r = api.put(
        f"/api/v1/me/devices/{s['device id']}/prekeys",
        {"cross_sig": s["cross signature"], "bundle_version": 1},
        format="json",
        **auth,
    )
    assert r.status_code == 200, f"cross-sign: {r.status_code}"

    # Publish the cross-signing identity and append a device-log record: both new
    # surfaces carry key material and must stay as silent as the rest.
    s["master public key"] = _b64_filled(32, 0x6D)
    r = api.put(
        "/api/v1/me/identity",
        {
            "master_pub": s["master public key"],
            "self_signing_pub": _b64_filled(32, 0x74),
            "user_signing_pub": _b64_filled(32, 0x75),
            "master_sig": _b64_filled(64, 0x76),
            "version": 1,
        },
        format="json",
        **auth,
    )
    assert r.status_code == 200, f"identity publish: {r.status_code}"
    s["device log blob"] = _b64_filled(min(DEVICELOG_BUCKETS), 0xD1)
    r = api.post(
        "/api/v1/me/devicelog",
        {"records": [{"blob": s["device log blob"]}]},
        format="json",
        **auth,
    )
    assert r.status_code == 201, f"devicelog append: {r.status_code}"
    r = api.get(f"/api/v1/users/{s['user id']}/devicelog", **auth)
    assert r.status_code == 200, f"devicelog read: {r.status_code}"

    # Upload + download an attachment (download answers via X-Accel-Redirect).
    upload_bytes = b"\x01" * min(ATTACHMENT_BUCKETS)
    r = api.post(
        "/api/v1/attachments",
        {"blob": SimpleUploadedFile("blob", upload_bytes)},
        format="multipart",
        **auth,
    )
    assert r.status_code == 201, f"upload: {r.status_code}"
    s["attachment id"] = r.json()["attachment_id"]
    r = api.get(f"/api/v1/attachments/{s['attachment id']}", **auth)
    assert r.status_code == 200, f"download: {r.status_code}"

    # Create a room and mint a LiveKit join token (local HS256 signing).
    s["room name blob"] = _b64_filled(min(NAME_BUCKETS), 0xB6)
    r = api.post(
        "/api/v1/rooms", {"name_blob": s["room name blob"]}, format="json", **auth
    )
    assert r.status_code == 201, f"room create: {r.status_code}"
    s["room id"] = r.json()["room_id"]
    r = api.post(f"/api/v1/rooms/{s['room id']}/token", **auth)
    assert r.status_code == 200, f"room token: {r.status_code}"
    s["livekit join token"] = r.json()["token"]
    return s


async def _scripted_fastapi_traffic(client, s):
    """The half FastAPI serves: the directory, the profile blobs, the key backup,
    a token rotation, and the logout that ends the session. Adds each payload and
    each issued token to the secret set."""
    from core.buckets import BACKUP_BUCKETS, PROFILE_BUCKETS

    auth = {"Authorization": f"Bearer {s['access token']}"}

    r = await client.get("/api/v1/users", headers=auth)
    assert r.status_code == 200, f"directory: {r.status_code}"

    s["profile blob"] = _b64_filled(min(PROFILE_BUCKETS), 0xC3)
    r = await client.put(
        "/api/v1/me/profile",
        json={"blob": s["profile blob"], "version": 1},
        headers=auth,
    )
    assert r.status_code == 200, f"profile write: {r.status_code}"
    r = await client.get(f"/api/v1/users/{s['user id']}/profile", headers=auth)
    assert r.status_code == 200, f"peer profile read: {r.status_code}"

    s["key backup blob"] = _b64_filled(min(BACKUP_BUCKETS), 0xB4)
    r = await client.put(
        "/api/v1/me/keybackup",
        json={"blob": s["key backup blob"], "version": 1},
        headers=auth,
    )
    assert r.status_code == 200, f"key backup write: {r.status_code}"
    r = await client.get("/api/v1/me/keybackup", headers=auth)
    assert r.status_code == 200, f"key backup read: {r.status_code}"

    # Rotation issues a second pair; both halves must stay out of every log line.
    r = await client.post("/api/v1/auth/refresh", json={"refresh": s["refresh token"]})
    assert r.status_code == 200, f"refresh: {r.status_code}"
    s["rotated access token"] = r.json()["access"]
    s["rotated refresh token"] = r.json()["refresh"]


async def _scripted_logout(client, s):
    """Last, because it ends every token of the device."""
    r = await client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {s['rotated access token']}"},
    )
    assert r.status_code == 204, f"logout: {r.status_code}"


async def _scripted_socket_traffic(s):
    """The realtime half: authenticated connect, a volatile signal round-trip to our own
    device, disconnect. Adds the signal blob to the secret set."""
    from channels.testing import WebsocketCommunicator

    from config.asgi import application

    comm = WebsocketCommunicator(
        application,
        "/ws",
        headers=[(b"authorization", f"Bearer {s['access token']}".encode())],
    )
    connected, _ = await comm.connect(timeout=2)
    assert connected, "socket handshake refused"
    s["signal blob"] = f"volatile-{random_secrets.token_hex(12)}"
    await comm.send_json_to(
        {"type": "signal", "to_device": s["device id"], "blob": s["signal blob"]}
    )
    frame = await comm.receive_json_from(timeout=2)
    assert frame == {"type": "signal", "blob": s["signal blob"]}, "signal did not relay"
    await comm.disconnect()


def scan(lines, secrets):
    """Every captured line vs every generated secret. Substring match: an id inside a
    traceback, a repr, or a formatted message is still a leak."""
    return [
        f"{label} leaked into: {line[:160]}"
        for line in lines
        for label, secret in secrets.items()
        if secret and str(secret) in line
    ]


async def run_audit(probe=None):
    """Run the scripted sequence under full capture. Returns (leaks, secrets, lines).

    `probe(secrets)` is a test hook, called inside the capture window after the
    scripted traffic, so the suite can prove the audit still catches a deliberate
    leak."""
    from channels.db import database_sync_to_async
    from httpx import ASGITransport, AsyncClient

    # Import the ASGI application before the capture opens. That import runs
    # django.setup(), which re-applies LOGGING through dictConfig and replaces the
    # handlers this audit swapped in. Inside the capture window it would kill the
    # capture halfway through, and every assertion after that point would grade an
    # empty list instead of the real log stream.
    import config.asgi

    transport = ASGITransport(app=config.asgi.application)
    lifespan = config.asgi.api_application.router.lifespan_context
    with capture_all_logging() as lines:
        logging.getLogger("ops.audit.canary").debug(CANARY_OPEN)
        async with lifespan(config.asgi.api_application):
            async with AsyncClient(
                transport=transport, base_url="http://testserver"
            ) as client:
                secrets = await _scripted_account_traffic(client)
                await database_sync_to_async(_scripted_rest_traffic)(secrets)
                await _scripted_envelope_traffic(client, secrets)
                await _scripted_fastapi_traffic(client, secrets)
                await _scripted_socket_traffic(secrets)
                await _scripted_logout(client, secrets)
        if probe is not None:
            probe(secrets)
        logging.getLogger("ops.audit.canary").debug(CANARY_CLOSE)
    if not any(CANARY_OPEN in line for line in lines):
        raise RuntimeError("log capture was not live; this audit proved nothing")
    if not any(CANARY_CLOSE in line for line in lines):
        raise RuntimeError(
            "log capture stopped before the run ended; this audit proved nothing"
        )
    return scan(lines, secrets), secrets, lines
