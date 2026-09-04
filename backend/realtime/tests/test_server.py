"""What a real server does with the gateway, as against what the application says.

Every other suite here drives the ASGI application directly, which is where the
close codes live and where the frame protocol is decided. Two lines of
`realtime/API.md` are not the application's to keep, though, and only a server
can settle them:

- A refusal sent before the accept — an unlisted Origin, or a bad header token —
  is a `websocket.close` at the ASGI layer, but a server has no accepted socket
  to send a close frame on. It answers the handshake with an HTTP failure
  instead, and the code never reaches the client. The documentation says so
  because of this test.
- `1012` on shutdown is uvicorn's, not this application's: uvicorn closes each
  live socket itself before the lifespan shutdown runs, so `gateway.drain` never
  sees them on the normal path.

The flags below are the ones `ops/systemd/chat.service` runs with, so a change to
either implementation is caught here rather than on the VPS.
"""

import asyncio
import socket
import threading

import pytest
import uvicorn
import websockets
from websockets.exceptions import ConnectionClosed, InvalidStatus

from .conftest import mint_access

pytestmark = pytest.mark.django_db(transaction=True)

STARTUP_TIMEOUT_SECONDS = 10


class Server:
    """One uvicorn process-in-a-thread, on a port the kernel picks.

    The socket is bound here rather than by uvicorn so the test knows the port
    without polling for it, and the server runs in a thread of its own with its
    own event loop — which is the shape production runs in, and the reason this
    file cannot use the in-process driver the rest of the suite uses.
    """

    def __init__(self):
        self.socket = socket.socket()
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(("127.0.0.1", 0))
        self.port = self.socket.getsockname()[1]
        self.server = uvicorn.Server(
            uvicorn.Config(
                "config.asgi:application",
                log_config=None,
                access_log=False,
                ws="websockets-sansio",
                timeout_graceful_shutdown=5,
            )
        )
        self.thread = threading.Thread(
            target=self.server.run, kwargs={"sockets": [self.socket]}, daemon=True
        )

    @property
    def url(self):
        return f"ws://127.0.0.1:{self.port}/ws"

    async def start(self):
        self.thread.start()
        async with asyncio.timeout(STARTUP_TIMEOUT_SECONDS):
            while not self.server.started:
                await asyncio.sleep(0.01)

    async def stop(self):
        self.server.should_exit = True
        async with asyncio.timeout(STARTUP_TIMEOUT_SECONDS):
            while self.thread.is_alive():
                await asyncio.sleep(0.01)


@pytest.fixture
async def server():
    running = Server()
    await running.start()
    try:
        yield running
    finally:
        await running.stop()


async def test_a_refused_origin_is_a_failed_handshake_not_a_close_code(
    server, active_user, device, settings
):
    """4403 is the documented meaning; 403 is what the client observes.

    The application closes with 4403 before accepting, and a server with no
    accepted socket can only answer the upgrade request. A client sees a failed
    handshake, so it must read one as an Origin refusal rather than wait for a
    code that never arrives.
    """
    settings.ALLOWED_WS_ORIGINS = ["https://chat.example"]
    access = await mint_access(active_user, device)

    with pytest.raises(InvalidStatus) as refusal:
        await websockets.connect(
            server.url,
            additional_headers={
                "authorization": f"Bearer {access}",
                "origin": "https://evil.example",
            },
        )

    assert refusal.value.response.status_code == 403


async def test_a_refused_token_is_a_failed_handshake_too(server, db):
    """Same shape as the Origin refusal, and for the same reason: the header path
    binds before the accept, so a token that fails ends the handshake."""
    with pytest.raises(InvalidStatus) as refusal:
        await websockets.connect(
            server.url, additional_headers={"authorization": "Bearer not-a-jwt"}
        )

    assert refusal.value.response.status_code == 403


async def test_a_shutdown_closes_a_live_socket_with_1012(
    server, active_user, device, settings
):
    """The drain window of `ops/systemd/chat.service`, exercised end to end: a
    deploy has to reach the client as a reconnect signal, not as a dropped
    connection it will retry blindly."""
    settings.ALLOWED_WS_ORIGINS = []
    access = await mint_access(active_user, device)

    async with websockets.connect(
        server.url, additional_headers={"authorization": f"Bearer {access}"}
    ) as client:
        await server.stop()

        with pytest.raises(ConnectionClosed) as closed:
            await client.recv()

    assert closed.value.rcvd is not None, "the socket dropped without a close frame"
    assert closed.value.rcvd.code == 1012
