"""The socket driver the gateway suites and the log-silence audit share.

**Why it is hand-written.** The two off-the-shelf candidates were measured against
this suite before it was written, and both lose something the suite exists to
prove:

- `starlette.testclient.TestClient.websocket_connect` is synchronous. It runs the
  application in an anyio blocking portal — a new thread and a new event loop for
  each socket — while `api/redis.py` and `realtime/bus.py` both key what they hold
  on the running loop. Measured: three `TestClient` tests leave three Redis
  clients behind, each on a loop that is already closed, and the autouse teardown
  in `conftest.py` cannot see any of them, because pytest-asyncio gives it a third
  loop again. A two-socket relay test would also put the two sockets on two loops,
  which is not the process this code runs in.
- `httpx-ws`'s `ASGIWebSocketTransport` keeps everything on one loop, but its
  network stream catches `Exception` from the application and turns it into a
  close with code `1011` and `str(exception)` as the reason. A gateway crash and a
  deliberate `4008` then look alike — which is the distinction `test_limits.py`
  exists to draw — and the exception text, which in this codebase can carry a
  device id, goes back over the wire. It is also two more hash-pinned wheels to
  vendor for the offline install, for a test-only concern.

So this speaks ASGI to the application directly, on the caller's own loop, with
two queues where the wire would be, and re-raises whatever the gateway raises.
"""

import asyncio
import json


class WebSocketCommunicator:
    """Drive `/ws` over raw ASGI, on the loop the test is running on."""

    def __init__(self, app, path, headers=None, outbound_max=0):
        """`outbound_max` bounds the queue that stands in for the wire, so a test
        can stop reading and produce the backpressure a real slow consumer
        produces. The default is unbounded, which is what every test that is not
        about backpressure wants."""
        self.app = app
        self.scope = {
            "type": "websocket",
            "asgi": {"version": "3.0", "spec_version": "2.3"},
            "http_version": "1.1",
            "scheme": "ws",
            "server": ("testserver", 80),
            "client": ("127.0.0.1", 12345),
            "root_path": "",
            "path": path,
            "raw_path": path.encode(),
            "query_string": b"",
            "headers": [(b"host", b"testserver"), *(headers or [])],
            "subprotocols": [],
            "state": {},
        }
        self._inbound = asyncio.Queue()
        self._outbound = asyncio.Queue(maxsize=outbound_max)
        self.task = None
        # The raw message the handshake ended on. Kept because a refusal and a
        # denial response are two different ASGI messages that both mean "not
        # accepted", and only one of them is a close code.
        self.handshake = None

    async def connect(self, timeout=2):
        """Returns `(accepted, code)`: the close code when the handshake is refused.

        A refusal is a close sent before the accept. A real server answers that
        with an HTTP failure and the code never reaches the client, which is what
        `realtime/API.md` documents; here it is visible, because this is the
        application's own output rather than a server's rendering of it.
        """
        self.task = asyncio.create_task(
            self.app(self.scope, self._inbound.get, self._outbound.put)
        )
        await self._inbound.put({"type": "websocket.connect"})
        message = self.handshake = await self.receive_output(timeout)
        if message["type"] == "websocket.accept":
            return True, message.get("subprotocol")
        return False, message.get("code", 1000)

    async def receive_output(self, timeout=2):
        """The next raw ASGI message the application sent.

        Waits on the application task as well as on the queue: without that, a
        gateway that raised would show up as a timeout with no traceback.
        """
        getter = asyncio.ensure_future(self._outbound.get())
        done, _pending = await asyncio.wait(
            {getter, self.task}, timeout=timeout, return_when=asyncio.FIRST_COMPLETED
        )
        if getter in done:
            return getter.result()
        getter.cancel()
        try:
            return self._outbound.get_nowait()
        except asyncio.QueueEmpty:
            pass
        if self.task in done:
            error = self.task.exception()
            if error is not None:
                raise error
            raise AssertionError("the gateway exited without producing output")
        raise TimeoutError(f"no output within {timeout}s")

    async def receive_json_from(self, timeout=2):
        message = await self.receive_output(timeout)
        assert message["type"] == "websocket.send", message
        return json.loads(message["text"])

    async def receive_nothing(self, timeout=0.2):
        """True when the application sent nothing for `timeout` seconds."""
        try:
            await asyncio.wait_for(asyncio.shield(self._outbound.get()), timeout)
        except TimeoutError:
            return True
        return False

    async def send_json_to(self, data):
        await self.send_to(text_data=json.dumps(data))

    async def send_to(self, text_data=None, bytes_data=None):
        message = {"type": "websocket.receive"}
        if bytes_data is not None:
            message["bytes"] = bytes_data
        else:
            message["text"] = text_data
        await self._inbound.put(message)

    async def disconnect(self, code=1000, timeout=2):
        """Drop the socket and wait for the gateway's cleanup to finish.

        Waiting is what makes the presence-offline assertions deterministic: the
        announcement is an effect of the cleanup, not of the disconnect frame.
        """
        await self._inbound.put({"type": "websocket.disconnect", "code": code})
        if self.task is not None and not self.task.done():
            try:
                await asyncio.wait_for(asyncio.shield(self.task), timeout)
            except TimeoutError:
                self.task.cancel()
