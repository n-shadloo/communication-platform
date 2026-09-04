"""The fixtures and helpers every gateway suite shares.

The socket driver itself is `realtime/tests/socket.py`, which the log-silence
audit imports too.
"""

import base64

import httpx
import pytest
from httpx import ASGITransport

from accounts.models import User
from api.auth import issue_full
from api.orm import run_unit
from api.redis import close_client
from config.asgi import application
from core.buckets import ENVELOPE_BUCKETS
from devices.models import Device
from realtime.bus import stop_subscriber
from realtime.tests.socket import WebSocketCommunicator

PASSWORD = "correct-horse-battery-staple"


@pytest.fixture(autouse=True)
async def release_the_loops_redis():
    """The bus and the room-presence sets build their Redis objects on the loop that
    first asks for one, and pytest-asyncio gives each test a loop of its own.
    Without this each test leaves a subscriber — with its reader task — and a
    client, both bound to a loop that is already gone. Same order as the lifespan
    shutdown: the subscriber before the client whose pool it borrowed."""
    yield
    await stop_subscriber()
    await close_client()


@pytest.fixture
def peer(db):
    return User.objects.create_user(username="bob", password=PASSWORD, is_active=True)


@pytest.fixture
def peer_device(peer):
    return Device.objects.create(
        user=peer,
        ik_pub=b"ik",
        spk_id=1,
        spk_pub=b"spk",
        spk_sig=b"sig",
        registration_id=2002,
    )


async def mint_access(user, device):
    """A valid full-scope access token for a test device. Off the loop because the
    token reads the device's two generation counters off the row."""
    return (await run_unit(issue_full, user, device))[0]


def envelope_blob(fill=b"e"):
    return base64.b64encode(fill * min(ENVELOPE_BUCKETS)).decode()


def ws(headers=None, outbound_max=0):
    return WebSocketCommunicator(
        application, "/ws", headers=headers or [], outbound_max=outbound_max
    )


def bearer(access):
    return [(b"authorization", f"Bearer {access}".encode())]


async def http_request(method, url, access, **kwargs):
    """Drive an HTTP route of the composed application from an async test.

    Awaited rather than driven through the root conftest's `AsgiClient`: that one
    calls `async_to_sync`, which raises on a thread that is already running a
    loop, and every test here is a coroutine. The lifespan is entered around the
    request alone, so the socket the test also holds is never inside it — the
    lifespan shutdown drains sockets, and draining the socket under test would be
    the harness answering its own question.
    """
    async with httpx.AsyncClient(
        transport=ASGITransport(app=application), base_url="http://testserver"
    ) as client:
        return await client.request(
            method,
            url,
            headers={"Authorization": f"Bearer {access}"},
            **kwargs,
        )


async def connect_ok(headers, outbound_max=0):
    comm = ws(headers, outbound_max=outbound_max)
    connected, _ = await comm.connect(timeout=2)
    assert connected, "expected the handshake to be accepted"
    return comm


async def expect_close(comm, code, timeout=2):
    out = await comm.receive_output(timeout)
    assert out["type"] == "websocket.close"
    assert out.get("code") == code


async def probe(comm, own_device_id):
    """Round-trip a self-signal. Frames are processed in order and every handler
    awaits its own publish, so when the probe comes back over the bus, every
    frame sent before it has been fully handled: a deterministic barrier."""
    await comm.send_json_to(
        {"type": "signal", "to_device": str(own_device_id), "blob": "probe"}
    )
    frame = await comm.receive_json_from(timeout=2)
    assert frame == {"type": "signal", "blob": "probe"}


def _table_counts():
    from django.apps import apps

    return {m._meta.label: m.objects.count() for m in apps.get_models()}


async def table_counts():
    return await run_unit(_table_counts)
