import asyncio
import time
import uuid
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.conf import settings
from .auth import authenticate_access, delete_envelopes, touch_active

AUTH_DEADLINE_SECONDS = 10
RATE_WINDOW_SECONDS = 1.0
RATE_MAX_IN_WINDOW = 100

class GatewayConsumer(AsyncJsonWebsocketConsumer):
    # ---- lifecycle -------------------------------------------------------
    async def connect(self):
        # Attributes first: the websocket.disconnect that follows every rejected
        # handshake still runs disconnect(), which must find them (else each origin
        # reject leaves an AttributeError traceback in the error log, §A11.4).
        self.user = None
        self.device = None
        self.device_group = None
        self.authed = False
        self.presence_targets = set()
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
            if self.device_group:
                await self.channel_layer.group_discard(self.device_group, self.channel_name)

    # ---- inbound ---------------------------------------------------------
    async def receive(self, text_data=None, bytes_data=None):
        if bytes_data is not None:
            await self.close(code=4008)          # this protocol is JSON text only
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
            # Undecodable JSON is a protocol violation, not a consumer crash — the WS
            # twin of the REST guard for malformed bodies (messaging/views.py). 4008
            # is the close §A6 assigns to protocol misuse.
            await self.close(code=4008)

    async def receive_json(self, content, **kwargs):
        if not isinstance(content, dict):
            # A JSON scalar/array frame decodes fine but has no .get() — same bug
            # class the REST ack guards against non-dict request.data.
            await self.close(code=4008)
            return
        mtype = content.get("type")
        if not self.authed:
            if mtype == "auth" and await self._bind(content.get("access") or ""):
                return
            await self.close(code=4001)
            return
        if mtype == "ack":
            await self._handle_ack(content)
        elif mtype == "signal":
            await self._handle_signal(content)
        elif mtype == "subscribe_presence":
            await self._handle_subscribe_presence(content)
        # Unknown types are ignored (but counted by the rate limiter above).

    async def _handle_ack(self, content):
        ids = content.get("ids") or []
        if not (isinstance(ids, list) and 0 < len(ids) <= 200):
            return
        try:
            # Unparsed, a non-UUID id reaches the uuid pk column and raises Django's
            # ValidationError — the identical 500 the REST ack guards against
            # (messaging/views.py). Malformed acks are dropped like malformed signals.
            parsed = [uuid.UUID(str(i)) for i in ids]
        except (AttributeError, TypeError, ValueError):
            return
        await delete_envelopes(self.device.id, parsed)

    async def _handle_signal(self, content):
        to_device = content.get("to_device")
        blob = content.get("blob")
        # Volatile relay: forward opaque ciphertext, drop if the target is offline, and NEVER
        # persist or log to_device/blob (§A6, §A11.4/5).
        if not to_device or not isinstance(blob, str) or len(blob) > settings.SIGNAL_MAX:
            return
        try:
            # Normalized, not raw: uuid.UUID accepts braced/urn/uppercase spellings that
            # would crash group_send (invalid group name) or silently miss the lowercase
            # group the target actually joined.
            to_device = str(uuid.UUID(str(to_device)))
        except (ValueError, TypeError):
            return
        await self.channel_layer.group_send(
            f"dev.{to_device}", {"type": "signal.relay", "blob": blob})

    async def _handle_subscribe_presence(self, content):
        ids = content.get("device_ids") or []
        if not isinstance(ids, list) or len(ids) > 500:
            return
        valid = set()
        for d in ids:
            try:
                valid.add(str(uuid.UUID(str(d))))  # normalized like _handle_signal
            except (ValueError, TypeError):
                continue
        self.presence_targets = valid
        await self._emit_presence("online")

    # ---- channel-layer events (server -> this socket) --------------------
    async def envelope_push(self, event):
        await self.send_json({"type": "envelope", "id": event["id"],
                              "seq": event["seq"], "blob": event["blob"]})

    async def signal_relay(self, event):
        await self.send_json({"type": "signal", "blob": event["blob"]})

    async def presence_signal(self, event):
        await self.send_json({"type": "presence", "device_id": event["device_id"],
                              "state": event["state"]})

    async def connection_close(self, event):
        await self.close(code=4003)              # device was revoked (§A8)

    # ---- helpers ---------------------------------------------------------
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
        # Presence is metadata the server inherently knows (socket up/down); only devices the
        # client authorized via subscribe_presence are told (§A6). No content is involved.
        if not self.device:
            return
        for dev_id in self.presence_targets:
            await self.channel_layer.group_send(
                f"dev.{dev_id}",
                {"type": "presence.signal", "device_id": str(self.device.id), "state": state})

    def _origin_ok(self):
        allowed = set(settings.ALLOWED_WS_ORIGINS or [])
        if not allowed:
            return True                          # unset allowlist = allow (dev)
        headers = dict(self.scope.get("headers") or {})
        origin = headers.get(b"origin")
        if origin is None:
            # Native clients (the Flutter app) send no Origin header at all. Origin is
            # a browser-only CSWSH defense: a browser always attaches its real origin
            # and cannot suppress it, while a native attacker can forge any value — so
            # rejecting the absent header locks out the primary client and stops
            # nobody. Present-but-unlisted origins (including "null") are refused.
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
