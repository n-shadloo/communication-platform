"""Backpressure and protocol bounds: every violation is a clean 4008 close, never a
consumer crash."""

import pytest

from .conftest import bearer, connect_ok, expect_close, mint_access

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
    from .conftest import probe

    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to({"type": "mystery"})
    await comm.send_json_to({})

    await probe(comm, device.id)
    await comm.disconnect()
