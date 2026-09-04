"""Device revocation reaches live sockets: the cascade's close event on the
device's bus topic closes the socket 4003, and the revoked token can never
reconnect.

Three publishers reach the same bus in this file, which is the point of it: the
test process itself, a FastAPI route, and the synchronous Django admin.
"""

import pytest

from api.orm import run_unit
from realtime import bus

from .conftest import bearer, connect_ok, expect_close, http_request, mint_access, ws

pytestmark = pytest.mark.django_db(transaction=True)


async def test_connection_close_event_closes_the_socket_4003(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await bus.publish(bus.device_topic(device.id), {"type": bus.CLOSE})

    await expect_close(comm, 4003)


async def test_rest_revocation_closes_the_live_socket_and_bars_reconnect(
    active_user, device
):
    """End to end: a sibling device calls DELETE /me/devices/{id}; the doomed
    device's socket drops 4003 and its outstanding token is dead for good."""
    from devices.models import Device

    doomed = await run_unit(
        Device.objects.create,
        user=active_user,
        ik_pub=b"ik",
        spk_id=2,
        spk_pub=b"spk",
        spk_sig=b"sig",
        registration_id=3003,
    )
    doomed_access = await mint_access(active_user, doomed)
    comm = await connect_ok(bearer(doomed_access))

    revoker = await mint_access(active_user, device)
    resp = await http_request("DELETE", f"/api/v1/me/devices/{doomed.id}", revoker)
    assert resp.status_code == 204

    await expect_close(comm, 4003)

    retry = ws(bearer(doomed_access))
    connected, code = await retry.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_admin_deactivation_closes_the_users_live_sockets(active_user, device):
    """REST re-checks is_active per request; the socket, authenticated at connect
    time, must be told, otherwise a deactivated account keeps its volatile relay
    until the connection happens to drop."""
    from django.contrib import admin as django_admin

    from accounts.admin import UserAdmin
    from accounts.models import User

    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    def deactivate_via_admin_action():
        UserAdmin(User, django_admin.site).deactivate_accounts(
            None, User.objects.filter(id=active_user.id)
        )

    await run_unit(deactivate_via_admin_action)

    await expect_close(comm, 4003)
