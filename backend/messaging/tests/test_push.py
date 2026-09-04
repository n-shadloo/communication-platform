"""The live push is an optimization layered over the durable mailbox."""

import asyncio

import pytest
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from messaging.models import QueuedEnvelope

from .conftest import envelope_blob

pytestmark = pytest.mark.django_db(transaction=True)

SEND_URL = "/api/v1/envelopes"


def receive(layer, channel, timeout=5):
    async def _receive():
        return await asyncio.wait_for(layer.receive(channel), timeout=timeout)

    return async_to_sync(_receive)()


def test_an_accepted_envelope_is_pushed_to_the_devices_group(
    http, active_user, device, bearer, bob_devices
):
    target = bob_devices[0]
    blob = envelope_blob(b"p")
    layer = get_channel_layer()
    # Stand in for the realtime consumer, which joins `dev.<device_id>` on connect.
    channel = async_to_sync(layer.new_channel)()
    async_to_sync(layer.group_add)(f"dev.{target.id}", channel)

    resp = http.post(
        SEND_URL,
        json={"messages": [{"device_id": str(target.id), "blob": blob}]},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 202
    message = receive(layer, channel)
    assert message["type"] == "envelope.push"
    assert message["blob"] == blob
    assert message["seq"] == 1


def test_a_send_to_a_device_with_no_socket_is_a_no_op(
    http, active_user, device, bearer, bob_devices
):
    """A group_send to a group with no members is dropped; the row is what matters."""
    resp = http.post(
        SEND_URL,
        json={
            "messages": [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}]
        },
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 202
    assert (
        QueuedEnvelope.objects.filter(recipient_device_id=bob_devices[0].id).count() == 1
    )


def test_a_dead_channel_layer_does_not_fail_the_send(
    http, active_user, device, bearer, bob_devices, settings
):
    """The rows are already committed, so a push failure must not 500; the client
    would retry and duplicate every envelope."""
    settings.CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {"hosts": ["redis://127.0.0.1:6390"]},
        },
    }

    resp = http.post(
        SEND_URL,
        json={
            "messages": [{"device_id": str(bob_devices[0].id), "blob": envelope_blob()}]
        },
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 202
    assert (
        QueuedEnvelope.objects.filter(recipient_device_id=bob_devices[0].id).count() == 1
    )
