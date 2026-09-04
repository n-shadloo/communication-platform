"""The two close codes that are not a client's fault: the shutdown drain and the
slow consumer.

Both are the gateway protecting the process rather than refusing a frame, and
both are in the close-code table of `realtime/API.md`.
"""

import pytest

from config.asgi import api_application
from realtime import bus, gateway

from .conftest import bearer, connect_ok, mint_access, probe, ws

pytestmark = pytest.mark.django_db(transaction=True)


async def test_a_lifespan_shutdown_closes_every_live_socket_with_1012(
    active_user, device
):
    """1012 is "service restart": a deploy must look like a reconnect to the
    client, not like the network going away."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)  # the socket is live and bound before the drain

    async with api_application.router.lifespan_context(api_application):
        pass

    out = await comm.receive_output(timeout=2)
    assert out["type"] == "websocket.close"
    assert out["code"] == 1012
    assert gateway.LIVE == set()


async def test_a_socket_that_never_reads_is_closed_as_a_slow_consumer_4008(
    active_user, device, monkeypatch
):
    """The send queue is the one per-connection buffer an outside writer fills, so
    it is the one that can grow without the client asking for anything. Past its
    bound the socket is dropped rather than held: 1 GB across every live socket is
    what makes the bound mandatory.
    """
    monkeypatch.setattr(gateway, "SEND_QUEUE_MAX", 2)
    # The wire holds one frame, so a peer that never reads blocks the send loop
    # after the first, and everything behind it piles up in the send queue.
    comm = await connect_ok(
        bearer(await mint_access(active_user, device)), outbound_max=1
    )

    for _ in range(10):
        await bus.relay_signal(str(device.id), "backlog")

    while True:
        out = await comm.receive_output(timeout=2)
        if out["type"] == "websocket.close":
            assert out["code"] == 4008
            return


async def test_an_unknown_path_is_refused_rather_than_answered_with_an_envelope(db):
    """A websocket to a path no route claims gets a close, not the JSON `not_found`
    envelope: rendering a response to a handshake needs the denial-response
    extension, which this application never declares and a server need not
    implement."""
    comm = ws()
    comm.scope["path"] = "/definitely-not-a-route"
    comm.scope["raw_path"] = b"/definitely-not-a-route"

    connected, code = await comm.connect(timeout=2)

    assert connected is False
    # A close, not `websocket.http.response.start`: the envelope the HTTP miss
    # renders would be a denial response, which this application never declares.
    assert comm.handshake["type"] == "websocket.close"
    assert code == 1000
