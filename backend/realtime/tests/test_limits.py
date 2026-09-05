"""Backpressure and protocol bounds: every violation is a clean 4008 close, never a
consumer crash.

Each bound is exercised at the value it admits as well as at the value past it.
A cap tested only from above passes just as well when it is off by one, and an
off-by-one here is either a client that cannot send its largest legal frame or a
budget that is one frame wider than the number the contract publishes.
"""

import asyncio
import json

import pytest

from realtime import gateway

from .conftest import bearer, connect_ok, expect_close, mint_access, probe

pytestmark = pytest.mark.django_db(transaction=True)


async def test_oversized_frame_closes_4008(active_user, device, settings):
    settings.WS_MAX_FRAME = 1024
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_to(text_data="x" * 1025)

    await expect_close(comm, 4008)


async def test_a_burst_over_the_rate_cap_closes_4008(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    for _ in range(101):  # RATE_MAX_IN_WINDOW is 100 per rolling second
        await comm.send_json_to({"type": "noop"})

    await expect_close(comm, 4008)


async def test_binary_frames_close_4008(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_to(bytes_data=b"\x00\x01")

    await expect_close(comm, 4008)


async def test_undecodable_json_closes_4008_instead_of_crashing(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_to(text_data="{definitely not json")

    await expect_close(comm, 4008)


async def test_non_object_json_closes_4008_instead_of_crashing(active_user, device):
    """'"hello"' decodes to a str with no .get(): the WS twin of the REST non-dict
    body guard."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_to(text_data='"hello"')

    await expect_close(comm, 4008)


async def test_unknown_frame_types_are_ignored(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "mystery"})
    await comm.send_json_to({})

    await probe(comm, device.id)
    await comm.disconnect()


async def test_a_json_array_frame_closes_4008_instead_of_crashing(active_user, device):
    """A list decodes fine and has no `.get()` either. The scalar case is the one
    people reach for; an array is what a client sends when it batches frames the
    way the REST surface takes them, and it must be refused just as cleanly."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_to(text_data='[{"type": "ack", "ids": []}]')

    await expect_close(comm, 4008)


async def test_a_frame_at_the_size_cap_is_read_and_the_byte_past_it_closes_4008(
    active_user, device, settings
):
    """The cap is what the frame may be, not what it must be under. A client whose
    largest legal envelope ack lands exactly on the bound has to be able to send
    it."""
    settings.WS_MAX_FRAME = 200
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    padding = settings.WS_MAX_FRAME - len(json.dumps({"type": "noop", "pad": ""}))
    at_the_cap = json.dumps({"type": "noop", "pad": "x" * padding})
    assert len(at_the_cap) == settings.WS_MAX_FRAME

    await comm.send_to(text_data=at_the_cap)
    await probe(comm, device.id)  # read, ignored as an unknown type, socket healthy

    one_past_the_cap = json.dumps({"type": "noop", "pad": "x" * (padding + 1)})
    await comm.send_to(text_data=one_past_the_cap)
    await expect_close(comm, 4008)


async def test_the_frame_at_the_rate_cap_is_the_last_one_admitted(
    active_user, device, monkeypatch
):
    """The window is pinned open so this measures the count and not the clock: the
    budget is what closes the socket, and it closes on the frame after the budget
    rather than on the one that spends it."""
    monkeypatch.setattr(gateway, "RATE_WINDOW_SECONDS", 60)
    monkeypatch.setattr(gateway, "RATE_MAX_IN_WINDOW", 5)
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    for _ in range(4):
        await comm.send_json_to({"type": "noop"})
    await probe(comm, device.id)  # the fifth frame of the window, and the barrier

    await comm.send_json_to({"type": "noop"})
    await expect_close(comm, 4008)


async def test_the_rate_window_rolls_so_a_paced_client_is_never_closed(
    active_user, device, monkeypatch
):
    """A fixed window would let a client spend its whole budget, wait, and be
    refused anyway until an arbitrary boundary passed. The budget is rolling: a
    frame older than the window is not held against the socket."""
    monkeypatch.setattr(gateway, "RATE_WINDOW_SECONDS", 0.05)
    monkeypatch.setattr(gateway, "RATE_MAX_IN_WINDOW", 6)
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    for _ in range(5):
        await comm.send_json_to({"type": "noop"})
    await probe(comm, device.id)  # the sixth, and the barrier that dates the first five
    await asyncio.sleep(0.1)  # twice the window: every one of them has aged out

    for _ in range(5):
        await comm.send_json_to({"type": "noop"})
    await probe(comm, device.id)
    await comm.disconnect()


async def test_an_empty_ack_list_is_dropped_rather_than_deleting_a_mailbox(
    active_user, device
):
    """`ids` is 1 to 200, and the lower bound is load-bearing: an empty list that
    reached the filter would carry no `id__in` term at all."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "ack", "ids": []})

    await probe(comm, device.id)
    await comm.disconnect()
