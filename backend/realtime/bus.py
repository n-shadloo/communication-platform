"""The fan-out bus: Redis publish and subscribe, one subscription for each worker.

Every frame that reaches a socket from outside its own connection arrives here.
A publisher names a topic and a JSON payload; the subscriber of each worker
process hands that payload to the sockets registered for the topic. Topics are
per device (`ws:dev:<device id>`) and per room (`ws:room:<room id>`), and a
payload's `type` names either a server frame of `realtime/API.md` or a control
event this module owns.

**Per-topic subscribe and unsubscribe, not one pattern subscription.** A pattern
would cost one command for the life of the process, at the price of delivering
every published frame to every worker, which then drops what it holds no socket
for. The common case makes that expensive: a live push to a device that is
offline is a whole envelope blob — up to a base64 bucket — carried across the
loopback socket only to be discarded. Per-topic instead: Redis drops the publish
server-side when nobody holds the topic, and the process pays one round trip on
each bind, room join and room leave, which is connection-lifecycle rate rather
than frame rate.

**Every publish is best-effort and silent.** The durable mailbox is the source of
truth for an envelope, and presence, signals and room traffic are volatile by
design, so a publish that fails must never fail the request that caused it. It is
never logged either: the message would carry a topic, and a topic names a device.
"""

import asyncio
import json

import redis
from django.conf import settings

from api.redis import get_client

# The control event. Not a server frame: it names an action on the socket rather
# than something to forward, and `realtime/gateway.py` is the only reader.
CLOSE = "socket.close"

# A reconnect is redis-py's own business — it re-issues SUBSCRIBE for every held
# topic on `on_connect` — so the reader only has to stop spinning while the
# connection is down.
RECONNECT_DELAY_SECONDS = 1.0

_subscribers = {}


async def _keep(response):
    """The push handler of every subscription this module opens.

    Asynchronous because the async parser awaits it: `_AsyncRESP3Parser` does
    `await self.handle_push_response(...)`, so a plain function here makes every
    push raise and the socket goes quiet rather than loud.

    redis-py's own default does two things this system cannot have. It logs each
    push at DEBUG as `Push response: [b'message', b'<topic>', b'<payload>']` —
    a device id and a ciphertext blob in a log line, which is invariant 6 — and,
    the first time a `PubSub` is built without a handler, it installs a
    `StreamHandler` to stdout on the `push_response` logger, outside Django's
    `LOGGING` and therefore outside the scrub filter, which is the same shape as
    a server's own access log. Passing this instead suppresses both: the
    library skips that setup entirely, and the payload is returned unchanged
    without being formatted into anything.

    `config/settings/base.py` claims the `push_response` logger as well, so a
    `PubSub` built anywhere else cannot install that handler either.
    """
    return response


def device_topic(device_id):
    return f"ws:dev:{device_id}"


def room_topic(room_id):
    return f"ws:room:{room_id}"


async def publish(topic, payload):
    """Best-effort fan-out of one payload. Never raises, never logs."""
    try:
        await get_client().publish(topic, json.dumps(payload))
    except Exception:
        return


async def publish_many(frames):
    """Best-effort fan-out of several payloads, in one round trip.

    Two paths reach here with more than one topic: a batch send, which is one
    envelope per recipient copy and capped at 256, and a presence announcement,
    which is one frame per subscribed device and capped at 500. Awaited one at a
    time those are that many sequential round trips on the event loop, which on
    one vCPU is the whole process: 256 sequential publishes cost 37.1 ms on
    loopback against 1.5 ms for the pipeline, and 500 cost 55.9 ms against 2.5 ms.

    `transaction=False`, because MULTI/EXEC buys nothing here — a publish takes
    effect the moment Redis reads it, and there is no state for the batch to be
    atomic over. Best-effort and silent like `publish`, with the same reason: the
    error would name a topic, and a topic names a device.
    """
    frames = list(frames)
    if not frames:
        return
    try:
        client = get_client()
        async with client.pipeline(transaction=False) as pipe:
            for topic, payload in frames:
                pipe.publish(topic, json.dumps(payload))
            await pipe.execute()
    except Exception:
        return


async def push_envelopes(envelopes):
    """The live half of a committed send. The queue rows are the source of truth.

    `blob` is the base64 the sender's own request carried, handed through rather
    than re-encoded from the stored bytes: the two are the same string, and
    producing it a second time costs 53 ms of event-loop CPU on the largest batch
    at the largest bucket.
    """
    await publish_many(
        (
            device_topic(device_id),
            {"type": "envelope", "id": envelope_id, "seq": seq, "blob": blob},
        )
        for device_id, envelope_id, seq, blob in envelopes
    )


async def relay_signal(device_id, blob):
    await publish(device_topic(device_id), {"type": "signal", "blob": blob})


async def announce_presence(device_ids, subject_id, state):
    """Tell each subscribed device that `subject_id` came online or went offline."""
    await publish_many(
        (
            device_topic(device_id),
            {"type": "presence", "device_id": subject_id, "state": state},
        )
        for device_id in device_ids
    )


async def relay_room(room_id, blob):
    await publish(
        room_topic(room_id), {"type": "room_signal", "room_id": room_id, "blob": blob}
    )


async def announce_room_presence(room_id, device_id, state):
    await publish(
        room_topic(room_id),
        {
            "type": "room_presence",
            "room_id": room_id,
            "device_id": device_id,
            "state": state,
        },
    )


def close_device_sockets(device_id):
    """Drop every live socket of a device whose tokens just died.

    Synchronous, and on a connection of its own: every caller is a unit of work
    or an admin action running on the ORM thread, where there is no event loop to
    borrow and where a loop built for the call would strand the shared async
    client of `api/redis.py` behind it. Revocation, logout and deactivation are
    rare enough that one connection each costs nothing.

    Best-effort and silent, because the error would name a device id.
    """
    client = None
    try:
        client = redis.Redis.from_url(settings.REDIS_URL)
        client.publish(device_topic(device_id), json.dumps({"type": CLOSE}))
    except Exception:
        pass
    finally:
        if client is not None:
            try:
                client.close()
            except Exception:
                pass


class Subscriber:
    """One publish-and-subscribe connection and one reader task for this worker.

    A sink is the synchronous `deliver` of one connection. Dispatch never awaits,
    so a socket that cannot keep up bounds itself in its own queue rather than
    holding up the fan-out of every other socket on the process.
    """

    def __init__(self):
        self._pubsub = None
        self._reader = None
        self._sinks = {}  # topic -> the sinks that hold it
        self._joined = {}  # topic -> the event the SUBSCRIBE confirmation sets

    async def subscribe(self, topic, sink):
        """Register `sink` for `topic`, and return once Redis has confirmed the
        subscription.

        Waiting for the confirmation is what makes a bind ordered: redis-py sends
        SUBSCRIBE without reading its reply, so a publish issued between the send
        and the confirmation would otherwise be dropped by a server that does not
        yet hold the subscription — which on the revocation path is a socket that
        outlives its own token.
        """
        holders = self._sinks.get(topic)
        if holders is not None:
            holders.add(sink)
            await self._joined[topic].wait()
            return
        self._sinks[topic] = {sink}
        joined = asyncio.Event()
        self._joined[topic] = joined
        if self._pubsub is None:
            self._pubsub = get_client().pubsub(push_handler_func=_keep)
        await self._pubsub.subscribe(topic)
        if self._reader is None:
            # Started only now: reading before the first subscription raises,
            # because the pubsub object holds no connection until then.
            self._reader = asyncio.create_task(self._read())
        await joined.wait()

    async def unsubscribe(self, topic, sink):
        holders = self._sinks.get(topic)
        if holders is None:
            return
        holders.discard(sink)
        if holders:
            return
        del self._sinks[topic]
        self._joined.pop(topic, None)
        try:
            await self._pubsub.unsubscribe(topic)
        except Exception:
            pass

    async def aclose(self):
        """Release the connection and the reader task of this worker."""
        if self._reader is not None:
            self._reader.cancel()
            try:
                await self._reader
            except asyncio.CancelledError:
                pass
            except Exception:
                pass
            self._reader = None
        if self._pubsub is not None:
            try:
                await self._pubsub.aclose()
            except Exception:
                pass
            self._pubsub = None
        self._sinks.clear()
        self._joined.clear()

    async def _read(self):
        while True:
            try:
                message = await self._pubsub.get_message(timeout=None)
            except (redis.RedisError, OSError):
                # The connection dropped. redis-py re-subscribes every held topic
                # when it comes back, so the only thing to do is wait and read
                # again. Silent: the message would name a topic.
                #
                # Only the connection classes are caught. A blanket except here
                # would turn a defect in this module into a socket that stays
                # open and silent forever, which is the failure that is hardest
                # to see from the outside.
                await asyncio.sleep(RECONNECT_DELAY_SECONDS)
                continue
            if message is not None:
                self._dispatch(message)

    def _dispatch(self, message):
        kind = message.get("type")
        channel = message.get("channel")
        topic = channel.decode() if isinstance(channel, bytes) else channel
        if kind == "subscribe":
            joined = self._joined.get(topic)
            if joined is not None:
                joined.set()
            return
        if kind != "message":
            return
        try:
            payload = json.loads(message["data"])
        except (TypeError, ValueError):
            return  # not ours, or truncated; never logged, it would name a topic
        for sink in tuple(self._sinks.get(topic, ())):
            sink(payload)


def get_subscriber():
    """The subscriber of the running loop, built on first use.

    Keyed by loop for the reason `api/redis.py` is: the connection underneath
    belongs to the loop that opened it. One process runs one loop and therefore
    holds one subscriber.
    """
    loop = asyncio.get_running_loop()
    subscriber = _subscribers.get(loop)
    if subscriber is None:
        subscriber = Subscriber()
        _subscribers[loop] = subscriber
    return subscriber


async def stop_subscriber():
    """Release the subscriber of the running loop, on a lifespan shutdown."""
    subscriber = _subscribers.pop(asyncio.get_running_loop(), None)
    if subscriber is not None:
        await subscriber.aclose()
