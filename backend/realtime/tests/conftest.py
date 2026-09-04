import base64

import httpx
import pytest
from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator
from httpx import ASGITransport

from accounts.models import User
from api.auth import issue_full
from api.redis import close_client
from config.asgi import api_application, application
from core.buckets import ENVELOPE_BUCKETS
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"


@pytest.fixture(autouse=True)
async def release_redis_client():
    """Room presence builds a Redis client on the loop that first asks for one, and
    pytest-asyncio gives each test a loop of its own. Without this each test leaves
    a client — and its open socket — bound to a loop that is already gone."""
    yield
    await close_client()


@pytest.fixture(autouse=True)
def in_memory_layer(settings):
    """Volatile means volatile: the whole suite runs on the in-memory layer, so a
    signal that survives a test could only have done so through the database, which
    is exactly what the zero-rows assertions check."""
    settings.CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}
    }


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


@database_sync_to_async
def mint_access(user, device):
    """A valid full-scope access token for a test device. DB-wrapped because the
    token reads the device's two generation counters off the row."""
    access, _refresh = issue_full(user, device)
    return access


def envelope_blob(fill=b"e"):
    return base64.b64encode(fill * min(ENVELOPE_BUCKETS)).decode()


def ws(headers=None):
    return WebsocketCommunicator(application, "/ws", headers=headers or [])


def bearer(access):
    return [(b"authorization", f"Bearer {access}".encode())]


async def http_request(method, url, access, **kwargs):
    """Drive an HTTP route of the composed application from an async test.

    Awaited rather than driven through the root conftest's `AsgiClient`: that one
    calls `async_to_sync`, which raises on a thread that is already running a
    loop, and every test here is a coroutine.
    """
    async with api_application.router.lifespan_context(api_application):
        async with httpx.AsyncClient(
            transport=ASGITransport(app=application), base_url="http://testserver"
        ) as client:
            return await client.request(
                method,
                url,
                headers={"Authorization": f"Bearer {access}"},
                **kwargs,
            )


async def connect_ok(headers):
    comm = ws(headers)
    connected, _ = await comm.connect(timeout=2)
    assert connected, "expected the handshake to be accepted"
    return comm


async def expect_close(comm, code, timeout=2):
    out = await comm.receive_output(timeout)
    assert out["type"] == "websocket.close"
    assert out.get("code") == code


async def probe(comm, own_device_id):
    """Round-trip a self-signal. Frames are processed in order, so when the probe
    comes back every previously sent frame has been fully handled: a deterministic
    barrier."""
    await comm.send_json_to(
        {"type": "signal", "to_device": str(own_device_id), "blob": "probe"}
    )
    frame = await comm.receive_json_from(timeout=2)
    assert frame == {"type": "signal", "blob": "probe"}


@database_sync_to_async
def table_counts():
    from django.apps import apps

    return {m._meta.label: m.objects.count() for m in apps.get_models()}
