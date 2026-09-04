import asyncio
import time
import uuid

from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.conf import settings

from .auth import _room_exists as _room_exists_query
from .auth import (
    authenticate_access,
    delete_envelopes,
    room_join_async,
    room_leave_async,
    touch_active,
)

AUTH_DEADLINE_SECONDS = 10
RATE_WINDOW_SECONDS = 1.0
RATE_MAX_IN_WINDOW = 100
ROOM_SUBSCRIPTIONS_MAX = 100  # bounded like presence_targets


class GatewayConsumer(AsyncJsonWebsocketConsumer):
    # ---- lifecycle -------------------------------------------------------
    async def connect(self):
        # Attributes first: the websocket.disconnect that follows every rejected
        # handshake still runs disconnect(), which must find them, else each origin
        # reject leaves an AttributeError traceback in the error log.
        self.user = None
        self.device = None
        self.device_group = None
        self.authed = False
        self.presence_targets = set()
        self.rooms = set()
        self._msg_times = []
        self._auth_task = None

        if not self._origin_ok():
            await self.close(code=4403)
            return

        token = self._header_token()
        if token is not None:
            if await self._bind(token):
                await self.accept()
            else:
                await self.close(code=4001)
            return

        # Browser path: accept unauthed, require an auth frame before the deadline.
        await self.accept()
        self._auth_task = asyncio.create_task(self._auth_deadline())

    async def _auth_deadline(self):
        try:
            await asyncio.sleep(AUTH_DEADLINE_SECONDS)
            if not self.authed:
                await self.close(code=4001)
        except asyncio.CancelledError:
            pass

    async def disconnect(self, code):
        if self._auth_task:
            self._auth_task.cancel()
        if self.authed:
            await self._emit_presence("offline")
            for room_id in list(getattr(self, "rooms", set())):
                await self._leave_room(room_id)
            if self.device_group:
                await self.channel_layer.group_discard(
                    self.device_group, self.channel_name
                )

    # ---- inbound ---------------------------------------------------------
    async def receive(self, text_data=None, bytes_data=None):
        if bytes_data is not None:
            await self.close(code=4008)  # this protocol is JSON text only
            return
        if text_data is not None and len(text_data) > settings.WS_MAX_FRAME:
            await self.close(code=4008)
            return
        if not self._rate_ok():
            await self.close(code=4008)
            return
        try:
            await super().receive(text_data=text_data)
        except ValueError:
            # Undecodable JSON is a protocol violation, not a consumer crash: the WS
            # twin of the REST guard for malformed bodies. 4008 is the protocol-misuse
            # close code.
            await self.close(code=4008)

    async def receive_json(self, content, **kwargs):
        if not isinstance(content, dict):
            # A JSON scalar or array frame decodes fine but has no .get(); the same
            # bug class the REST ack guards against.
            await self.close(code=4008)
            return

        message_type = content.get("type")
        if not self.authed:
            if message_type == "auth" and await self._bind(content.get("access") or ""):
                return
            await self.close(code=4001)
            return

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
        if not (isinstance(ids, list) and 0 < len(ids) <= 200):
            return
        try:
            # Unparsed, a non-UUID id reaches the uuid pk column and raises Django's
            # ValidationError, the identical 500 the REST ack guards against.
            # Malformed acks are dropped like malformed signals.
            parsed = [uuid.UUID(str(i)) for i in ids]
        except (AttributeError, TypeError, ValueError):
            return
        await delete_envelopes(self.device.id, parsed)

    async def _handle_signal(self, content):
        to_device = content.get("to_device")
        blob = content.get("blob")
        # Volatile relay: forward opaque ciphertext, drop it if the target is offline,
        # and never persist or log to_device or blob.
        if not to_device or not isinstance(blob, str) or len(blob) > settings.SIGNAL_MAX:
            return
        try:
            # Normalized, not raw: uuid.UUID accepts braced/urn/uppercase spellings
            # that would crash group_send (invalid group name) or silently miss the
            # lowercase group the target actually joined.
            to_device = str(uuid.UUID(str(to_device)))
        except (ValueError, TypeError):
            return
        await self.channel_layer.group_send(
            f"dev.{to_device}", {"type": "signal.relay", "blob": blob}
        )

    async def _handle_subscribe_presence(self, content):
        ids = content.get("device_ids") or []
        if not isinstance(ids, list) or len(ids) > 500:
            return
        valid = set()
        for device_id in ids:
            try:
                valid.add(
                    str(uuid.UUID(str(device_id)))
                )  # normalized like _handle_signal
            except (ValueError, TypeError):
                continue
        self.presence_targets = valid
        await self._emit_presence("online")

    async def _handle_room_subscribe(self, content):
        raw_id = content.get("room_id")
        if not raw_id:
            return
        try:
            # Normalized like _handle_signal: raw client input into the UUID pk lookup
            # raises ValidationError, a consumer crash whose traceback embeds the
            # value, and alternate spellings would split the group namespace.
            room_id = str(uuid.UUID(str(raw_id)))
        except (ValueError, TypeError):
            return
        if room_id not in self.rooms and len(self.rooms) >= ROOM_SUBSCRIPTIONS_MAX:
            return
        if not await self._room_exists(room_id):
            return

        self.rooms.add(room_id)
        await self.channel_layer.group_add(f"room.{room_id}", self.channel_name)
        await self._room_presence(room_id, "join")
        await room_join_async(room_id, self.device.id)

    async def _handle_room_leave(self, content):
        room_id = str(content.get("room_id") or "")
        if room_id in self.rooms:
            await self._leave_room(room_id)

    async def _handle_room_signal(self, content):
        room_id = str(content.get("room_id") or "")
        blob = content.get("blob")
        # Ephemeral room text/state: relayed to the room group, never persisted or
        # logged.
        if (
            room_id in self.rooms
            and isinstance(blob, str)
            and len(blob) <= settings.SIGNAL_MAX
        ):
            await self.channel_layer.group_send(
                f"room.{room_id}",
                {"type": "room.relay", "room_id": room_id, "blob": blob},
            )

    # ---- channel-layer events (server -> this socket) --------------------
    async def envelope_push(self, event):
        await self.send_json(
            {
                "type": "envelope",
                "id": event["id"],
                "seq": event["seq"],
                "blob": event["blob"],
            }
        )

    async def signal_relay(self, event):
        await self.send_json({"type": "signal", "blob": event["blob"]})

    async def presence_signal(self, event):
        await self.send_json(
            {"type": "presence", "device_id": event["device_id"], "state": event["state"]}
        )

    async def room_relay(self, event):
        await self.send_json(
            {"type": "room_signal", "room_id": event["room_id"], "blob": event["blob"]}
        )

    async def room_presence(self, event):
        await self.send_json(
            {
                "type": "room_presence",
                "room_id": event["room_id"],
                "device_id": event["device_id"],
                "state": event["state"],
            }
        )

    async def connection_close(self, event):
        await self.close(code=4003)  # device was revoked

    # ---- helpers ---------------------------------------------------------
    # The auth-module existence query, bound as a method so tests can patch it.
    _room_exists = staticmethod(_room_exists_query)

    async def _leave_room(self, room_id):
        self.rooms.discard(room_id)
        await self._room_presence(room_id, "leave")
        await room_leave_async(room_id, self.device.id)
        await self.channel_layer.group_discard(f"room.{room_id}", self.channel_name)

    async def _room_presence(self, room_id, state):
        await self.channel_layer.group_send(
            f"room.{room_id}",
            {
                "type": "room.presence",
                "room_id": room_id,
                "device_id": str(self.device.id),
                "state": state,
            },
        )

    async def _bind(self, token_str):
        result = await authenticate_access(token_str)
        if result is None:
            return False
        self.user, self.device = result
        self.device_group = f"dev.{self.device.id}"
        await self.channel_layer.group_add(self.device_group, self.channel_name)
        self.authed = True
        if self._auth_task:
            self._auth_task.cancel()
        await touch_active(self.device.id)
        return True

    async def _emit_presence(self, state):
        # Presence is metadata the server inherently knows (socket up/down); only
        # devices the client authorized via subscribe_presence are told. No content
        # is involved.
        if not self.device:
            return
        for device_id in self.presence_targets:
            await self.channel_layer.group_send(
                f"dev.{device_id}",
                {
                    "type": "presence.signal",
                    "device_id": str(self.device.id),
                    "state": state,
                },
            )

    def _origin_ok(self):
        allowed = set(settings.ALLOWED_WS_ORIGINS or [])
        if not allowed:
            return True  # unset allowlist = allow (dev)
        headers = dict(self.scope.get("headers") or {})
        origin = headers.get(b"origin")
        if origin is None:
            # Native clients (the Flutter app) send no Origin header at all. Origin
            # is a browser-only CSWSH defense: a browser always attaches its real
            # origin and cannot suppress it, while a native attacker can forge any
            # value, so rejecting the absent header locks out the primary client and
            # stops nobody. Present-but-unlisted origins (including "null") are
            # refused.
            return True
        return origin.decode() in allowed

    def _header_token(self):
        headers = dict(self.scope.get("headers") or {})
        auth = headers.get(b"authorization")
        if not auth:
            return None
        parts = auth.decode().split()
        return parts[1] if len(parts) == 2 and parts[0] == "Bearer" else None

    def _rate_ok(self):
        now = time.monotonic()
        self._msg_times = [t for t in self._msg_times if now - t < RATE_WINDOW_SECONDS]
        self._msg_times.append(now)
        return len(self._msg_times) <= RATE_MAX_IN_WINDOW
