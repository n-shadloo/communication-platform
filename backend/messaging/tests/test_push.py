"""The live push is an optimization layered over the durable mailbox."""

import json
import time

import pytest
import redis
from redis.asyncio import Redis

from devices.models import Device
from messaging.models import QueuedEnvelope
from realtime import bus

from .conftest import envelope_blob

pytestmark = pytest.mark.django_db(transaction=True)

SEND_URL = "/api/v1/envelopes"
DEAD_REDIS_URL = "redis://127.0.0.1:6390"


class Listener:
    """Stand in for the gateway, which subscribes to `ws:dev:<device id>` on bind.

    A real subscription on the real bus, because the bus is the contract under
    test: what the route publishes has to be what a socket would have received.

    Synchronous redis-py, not the async client the gateway uses: the send route is
    driven by the synchronous test client, which builds a fresh event loop for
    each call, and an async connection belongs to the loop that opened it — read
    from a second loop it never returns.
    """

    def __init__(self, url, topic):
        self.topic = topic
        self._client = redis.Redis.from_url(url)
        # The same push handler the bus passes, for the same reason: redis-py's
        # default logs the topic and the payload it just received.
        self._pubsub = self._client.pubsub(push_handler_func=lambda response: response)

    def __enter__(self):
        self._pubsub.subscribe(self.topic)
        # Read the SUBSCRIBE confirmation before the test publishes anything: the
        # command is sent without waiting for its reply, and Redis drops a publish
        # that lands before the server holds the subscription.
        self._await_kind("subscribe")
        return self

    def __exit__(self, *_exc):
        self._pubsub.close()
        self._client.close()

    def _await_kind(self, kind, timeout=5):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                raise AssertionError(f"no {kind} message on {self.topic} in {timeout}s")
            message = self._pubsub.get_message(timeout=left)
            if message is not None and message["type"] == kind:
                return message

    def receive(self, timeout=5):
        return json.loads(self._await_kind("message", timeout)["data"])

    def received_nothing(self, timeout=0.5):
        deadline = time.monotonic() + timeout
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return True
            message = self._pubsub.get_message(timeout=left)
            if message is not None and message["type"] == "message":
                return False


@pytest.fixture
def listener(settings):
    def build(device_id):
        return Listener(settings.REDIS_URL, bus.device_topic(device_id))

    return build


def test_an_accepted_envelope_is_pushed_to_the_devices_topic(
    http, active_user, device, bearer, bob_devices, listener
):
    target = bob_devices[0]
    blob = envelope_blob(b"p")

    with listener(target.id) as subscriber:
        resp = http.post(
            SEND_URL,
            json={"messages": [{"device_id": str(target.id), "blob": blob}]},
            headers=bearer(active_user, device),
        )

        assert resp.status_code == 202
        message = subscriber.receive()

    assert message["type"] == "envelope"
    assert message["blob"] == blob
    assert message["seq"] == 1


def test_a_send_to_a_device_with_no_socket_is_a_no_op(
    http, active_user, device, bearer, bob_devices
):
    """A publish to a topic nobody holds is dropped by Redis; the row is what
    matters."""
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


def test_a_dead_bus_does_not_fail_the_send(
    http, active_user, device, bearer, bob_devices, monkeypatch
):
    """The rows are already committed, so a push failure must not 500; the client
    would retry and duplicate every envelope.

    Only the bus is pointed at the dead port. Redis itself has to stay up, because
    the rate limiter of this route fails closed and would answer 503 before the
    send ever ran — which would pass this assertion for the wrong reason.
    """
    monkeypatch.setattr(bus, "get_client", lambda: Redis.from_url(DEAD_REDIS_URL))

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


def test_a_rolled_back_send_publishes_nothing(
    http, active_user, device, bearer, bob_devices, listener, monkeypatch
):
    """The publish is after the commit, never inside the transaction.

    A frame announced for a row a rollback then takes away is worse than no frame
    at all: the client would ack an envelope id this server has never held, and
    the ack — which matches nothing — would look to it like delivery succeeded.

    The mutation is the last statement of the unit, so the counters really have
    moved when it fails; `queue_seq` back at 0 is what proves the rollback
    happened rather than that the unit never ran.
    """
    target = bob_devices[0]

    def explode(*_args, **_kwargs):
        raise RuntimeError("the insert fails after the counters have moved")

    monkeypatch.setattr(QueuedEnvelope.objects, "bulk_create", explode)

    with listener(target.id) as subscriber:
        # The failure reaches the test rather than rendering the `server_error`
        # envelope: Starlette's error middleware re-raises after answering, and
        # the ASGI transport this client uses re-raises in turn, which is what
        # keeps a 500 from being mistaken for a passing request.
        with pytest.raises(RuntimeError):
            http.post(
                SEND_URL,
                json={
                    "messages": [{"device_id": str(target.id), "blob": envelope_blob()}]
                },
                headers=bearer(active_user, device),
            )

        assert subscriber.received_nothing()

    assert QueuedEnvelope.objects.filter(recipient_device_id=target.id).count() == 0
    assert Device.objects.get(id=target.id).queue_seq == 0
