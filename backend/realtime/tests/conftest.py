import base64

import pytest
from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator

from accounts.models import User
from accounts.tokens import issue_full
from config.asgi import application
from core.buckets import ENVELOPE_BUCKETS
from devices.models import Device

PASSWORD = "correct-horse-battery-staple"


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
    blacklist app records every refresh issued."""
    access, _refresh = issue_full(user, device)
    return access


def envelope_blob(fill=b"e"):
    return base64.b64encode(fill * min(ENVELOPE_BUCKETS)).decode()


def ws(headers=None):
    return WebsocketCommunicator(application, "/ws", headers=headers or [])


def bearer(access):
    return [(b"authorization", f"Bearer {access}".encode())]


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
