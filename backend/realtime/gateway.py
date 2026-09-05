"""The `/ws` gateway: one Starlette WebSocket route on the FastAPI application.

One socket carries envelope delivery, volatile device-to-device signals, presence
and ephemeral room traffic. The wire contract is `realtime/API.md` and this module
is the whole of its server half; `realtime/bus.py` carries a frame between two
sockets, wherever in the process set they are.

A connection authenticates before it is accepted, so every accepted socket is
already bound to a device. It is then a receive loop and a send loop in one task
group, plus the watch that turns an out-of-band stop — a revocation, a slow
consumer — into a close code. Every task of the group dies with the first one that
raises, and the cleanup that follows runs on every exit path alike: presence
offline to the devices the socket named, a room leave for every room it held, and
the unsubscription of every topic.

Nothing here is persisted and nothing here is logged. The database is reached only
through `api/orm.py`, on the thread the ORM owns, and Redis only through the async
client of `api/redis.py`, so no frame ever blocks the event loop.
"""

import asyncio
import json
import time
import uuid

from django.conf import settings
from fastapi import WebSocket

from realtime import auth, bus
from voicerooms.presence import room_join, room_leave

RATE_WINDOW_SECONDS = 1.0
RATE_MAX_IN_WINDOW = 100
ROOM_SUBSCRIPTIONS_MAX = 100  # bounded like presence_targets
PRESENCE_TARGETS_MAX = 500
ACK_IDS_MAX = 200

# The bound on the one per-connection buffer that an outside writer fills. A
# socket that cannot drain it is a slow consumer and closes with 4008 rather than
# growing a queue the process has no memory for: 1 GB across every live socket is
# what makes a bound mandatory and this number small.
SEND_QUEUE_MAX = 256

# The shutdown close code. `1012` is "service restart", which tells the client to
# reconnect rather than to treat a deploy as a network failure. The drain waits
# for the sockets to answer, but never past this, because a shutdown that a stuck
# socket can hold open is not a shutdown.
SHUTDOWN_CODE = 1012
DRAIN_TIMEOUT_SECONDS = 5

PATH = "/ws"

# Every accepted connection of this worker, so a lifespan shutdown can drain them.
LIVE = set()


class _Stop(Exception):
    """Tear down the task group. The code to close with is on the connection."""


async def gateway(websocket: WebSocket):
    await Connection(websocket).serve(_header_token(websocket))


async def drain():
    """Close every live socket of this worker with `1012`.

    uvicorn's own graceful shutdown closes the sockets with the same code before
    the lifespan shutdown reaches this, so in a normal stop it finds nothing
    left. It is what covers a shutdown that arrives by any other route.
    """
    connections = tuple(LIVE)
    for connection in connections:
        connection.stop(SHUTDOWN_CODE)
    if not connections:
        return
    try:
        async with asyncio.timeout(DRAIN_TIMEOUT_SECONDS):
            for connection in connections:
                await connection.wait_closed()
    except TimeoutError:
        return  # silent: naming the socket that hung would name its device


class Connection:
    """One socket: its identity, its bounded buffers, and its two loops."""

    def __init__(self, websocket):
        self.websocket = websocket
        self.user = None
        self.device = None
        self.device_topic = None
        self.presence_targets = set()
        self.rooms = set()
        self._msg_times = []
        self._outbox = asyncio.Queue(maxsize=SEND_QUEUE_MAX)
        self._stop = asyncio.Event()
        self._closed = asyncio.Event()
        self._close_code = None

    # ---- lifecycle -------------------------------------------------------
    async def serve(self, token):
        if token is None or not await self._bind(token):
            # Decided before the accept, so this is a refused handshake rather
            # than a close frame: a server answers the upgrade request with an
            # HTTP failure and there is no socket to carry a code on.
            # `realtime/API.md` documents both halves.
            await self.websocket.close()
            return
        try:
            await self.websocket.accept()
            LIVE.add(self)
            await self._loops()
        finally:
            LIVE.discard(self)
            await self._cleanup()
            await self._close()
            self._closed.set()

    async def wait_closed(self):
        await self._closed.wait()

    async def _loops(self):
        try:
            async with asyncio.TaskGroup() as group:
                group.create_task(self._receive_loop())
                group.create_task(self._send_loop())
                group.create_task(self._stop_watch())
        except* _Stop:
            pass

    def stop(self, code):
        """End this connection with `code`, from anywhere including a sync sink.

        First writer wins: a socket that trips the rate cap while a revocation is
        already in flight closes for one reason, not two.
        """
        if self._close_code is None:
            self._close_code = code
        self._stop.set()

    async def _stop_watch(self):
        await self._stop.wait()
        raise _Stop

    async def _cleanup(self):
        await self._emit_presence("offline")
        for room_id in tuple(self.rooms):
            await self._leave_room(room_id)
        await bus.get_subscriber().unsubscribe(self.device_topic, self.deliver)

    async def _close(self):
        if self._close_code is None:
            return  # the client went away first; there is nothing to answer
        try:
            await self.websocket.close(code=self._close_code)
        except RuntimeError:
            # Starlette refuses a second close, and the client may already have
            # dropped. Silent: the message would name the socket.
            pass

    # ---- the bus sink ----------------------------------------------------
    def deliver(self, payload):
        """Hand one bus payload to this socket. Synchronous, and never blocks:
        the subscriber fans out to every sink in turn, so an await here would let
        one slow socket hold up every other socket of the process."""
        if payload.get("type") == bus.CLOSE:
            self.stop(4003)
            return
        try:
            self._outbox.put_nowait(payload)
        except asyncio.QueueFull:
            self.stop(4008)  # a slow consumer is a protocol violation

    async def _send_loop(self):
        while True:
            frame = await self._outbox.get()
            try:
                await self.websocket.send_text(json.dumps(frame))
            except (RuntimeError, OSError):
                self.stop(None)
                raise _Stop from None

    # ---- inbound ---------------------------------------------------------
    async def _receive_loop(self):
        while True:
            message = await self.websocket.receive()
            if message["type"] == "websocket.disconnect":
                self.stop(None)
                raise _Stop
            if message.get("bytes") is not None:
                self._violation()  # this protocol is JSON text only
            text = message.get("text") or ""
            if len(text) > settings.WS_MAX_FRAME:
                self._violation()
            if not self._rate_ok():
                self._violation()
            try:
                content = json.loads(text)
            except ValueError:
                # Undecodable JSON is a protocol violation, not a gateway crash:
                # the WS twin of the REST guard for malformed bodies.
                self._violation()
            if not isinstance(content, dict):
                # A JSON scalar or array frame decodes fine but has no `.get()`;
                # the same bug class the REST ack guards against.
                self._violation()
            await self._handle(content)

    def _violation(self):
        self.stop(4008)
        raise _Stop

    async def _handle(self, content):
        message_type = content.get("type")
        if message_type == "ack":
            await self._handle_ack(content)
        elif message_type == "signal":
            await self._handle_signal(content)
        elif message_type == "subscribe_presence":
            await self._handle_subscribe_presence(content)
        elif message_type == "room_subscribe":
            await self._handle_room_subscribe(content)
        elif message_type == "room_leave":
            await self._handle_room_leave(content)
        elif message_type == "room_signal":
            await self._handle_room_signal(content)
        # Unknown types are ignored (but counted by the rate limiter above).

    async def _handle_ack(self, content):
        ids = content.get("ids") or []
        if not (isinstance(ids, list) and 0 < len(ids) <= ACK_IDS_MAX):
            return
        try:
            # Unparsed, a non-UUID id reaches the uuid pk column and raises
            # Django's ValidationError, the identical 500 the REST ack guards
            # against. Malformed acks are dropped like malformed signals.
            parsed = [uuid.UUID(str(i)) for i in ids]
        except (AttributeError, TypeError, ValueError):
            return
        await auth.delete_envelopes(self.device.id, parsed)

    async def _handle_signal(self, content):
        to_device = content.get("to_device")
        blob = content.get("blob")
        # Volatile relay: forward opaque ciphertext, drop it if the target is
        # offline, and never persist or log to_device or blob.
        if not to_device or not isinstance(blob, str) or len(blob) > settings.SIGNAL_MAX:
            return
        try:
            # Normalized, not raw: uuid.UUID accepts braced/urn/uppercase
            # spellings, and a topic built from one of those is a topic the
            # target never subscribed to.
            to_device = str(uuid.UUID(str(to_device)))
        except (ValueError, TypeError):
            return
        await bus.relay_signal(to_device, blob)

    async def _handle_subscribe_presence(self, content):
        ids = content.get("device_ids") or []
        if not isinstance(ids, list) or len(ids) > PRESENCE_TARGETS_MAX:
            return
        valid = set()
        for device_id in ids:
            try:
                # Normalized like _handle_signal.
                valid.add(str(uuid.UUID(str(device_id))))
            except (ValueError, TypeError):
                continue
        self.presence_targets = valid
        await self._emit_presence("online")

    async def _handle_room_subscribe(self, content):
        raw_id = content.get("room_id")
        if not raw_id:
            return
        try:
            # Normalized like _handle_signal: raw client input into the UUID pk
            # lookup raises ValidationError, a crash whose traceback embeds the
            # value, and alternate spellings would split the topic namespace.
            room_id = str(uuid.UUID(str(raw_id)))
        except (ValueError, TypeError):
            return
        if room_id not in self.rooms and len(self.rooms) >= ROOM_SUBSCRIPTIONS_MAX:
            return
        if not await auth.room_exists(room_id):
            return

        self.rooms.add(room_id)
        await bus.get_subscriber().subscribe(bus.room_topic(room_id), self.deliver)
        await bus.announce_room_presence(room_id, str(self.device.id), "join")
        await room_join(room_id, self.device.id)

    async def _handle_room_leave(self, content):
        room_id = str(content.get("room_id") or "")
        if room_id in self.rooms:
            await self._leave_room(room_id)

    async def _handle_room_signal(self, content):
        room_id = str(content.get("room_id") or "")
        blob = content.get("blob")
        # Ephemeral room text and state: relayed to the room's subscribers, never
        # persisted or logged.
        if (
            room_id in self.rooms
            and isinstance(blob, str)
            and len(blob) <= settings.SIGNAL_MAX
        ):
            await bus.relay_room(room_id, blob)

    # ---- helpers ---------------------------------------------------------
    async def _leave_room(self, room_id):
        self.rooms.discard(room_id)
        await bus.announce_room_presence(room_id, str(self.device.id), "leave")
        await room_leave(room_id, self.device.id)
        await bus.get_subscriber().unsubscribe(bus.room_topic(room_id), self.deliver)

    async def _bind(self, token_str):
        result = await auth.authenticate_access(token_str)
        if result is None:
            return False
        self.user, self.device = result
        self.device_topic = bus.device_topic(self.device.id)
        await bus.get_subscriber().subscribe(self.device_topic, self.deliver)
        await auth.touch_active(self.device.id)
        return True

    async def _emit_presence(self, state):
        # Presence is metadata the server inherently knows (socket up or down);
        # only the devices the client authorized through subscribe_presence are
        # told. No content is involved. One round trip for the whole set, because
        # the set holds up to PRESENCE_TARGETS_MAX and this runs on the receive
        # loop and again on every disconnect.
        await bus.announce_presence(self.presence_targets, str(self.device.id), state)

    def _rate_ok(self):
        now = time.monotonic()
        self._msg_times = [t for t in self._msg_times if now - t < RATE_WINDOW_SECONDS]
        self._msg_times.append(now)
        return len(self._msg_times) <= RATE_MAX_IN_WINDOW


def _header_token(websocket):
    header = websocket.headers.get("authorization")
    if not header:
        return None
    parts = header.split()
    return parts[1] if len(parts) == 2 and parts[0] == "Bearer" else None
