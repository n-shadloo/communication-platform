"""The socket authenticates with REST's strength: full scope, live device, matching
token_generation, active user (§A8) — and a failed handshake joins no group (§A6)."""
import pytest
from channels.db import database_sync_to_async
from channels.layers import get_channel_layer
from django.utils import timezone

from accounts.tokens import issue_register_scope

from .conftest import bearer, connect_ok, expect_close, mint_access, probe, ws

pytestmark = pytest.mark.django_db(transaction=True)


async def test_header_auth_path_connects(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)
    await comm.disconnect()


async def test_first_frame_auth_path_connects(active_user, device):
    """Browsers can't set WS headers (§A6): connect bare, then authenticate in-band."""
    comm = await connect_ok([])
    await comm.send_json_to({"type": "auth",
                             "access": await mint_access(active_user, device)})
    await probe(comm, device.id)
    await comm.disconnect()


async def test_connect_touches_last_active_date(active_user, device):
    assert device.last_active_date is None
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)

    refreshed = await database_sync_to_async(
        lambda: type(device).objects.get(id=device.id))()
    assert refreshed.last_active_date == timezone.now().date()
    await comm.disconnect()


async def test_garbage_token_closes_4001(db):
    comm = ws(bearer("not-a-jwt"))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_refresh_token_is_not_an_access_token(active_user, device):
    """A refresh JWT is validly signed but has the wrong token_type — REST rejects it
    and so must the socket."""
    from accounts.tokens import issue_full
    _access, refresh = await database_sync_to_async(issue_full)(active_user, device)

    comm = ws(bearer(refresh))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_register_scope_token_closes_4001_and_joins_no_group(active_user):
    """`register` scope buys exactly one REST endpoint and no socket (§A8)."""
    token = await database_sync_to_async(issue_register_scope)(active_user)

    comm = ws(bearer(token))
    connected, code = await comm.connect(timeout=2)

    assert (connected, code) == (False, 4001)
    assert get_channel_layer().groups == {}


async def test_register_scope_with_device_claims_still_closes_4001(active_user, device):
    """Scope is enforced in its own right, not via the missing device claim: even a
    register-scope token carrying a live device's id and tgen opens no socket (§A8)."""
    from rest_framework_simplejwt.tokens import AccessToken

    def forge():
        token = AccessToken.for_user(active_user)
        token["device_id"] = str(device.id)
        token["tgen"] = device.token_generation
        token["scope"] = "register"
        return str(token)

    comm = ws(bearer(await database_sync_to_async(forge)()))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_register_scope_token_via_auth_frame_closes_4001(active_user):
    token = await database_sync_to_async(issue_register_scope)(active_user)
    comm = await connect_ok([])

    await comm.send_json_to({"type": "auth", "access": token})

    await expect_close(comm, 4001)
    assert get_channel_layer().groups == {}


async def test_revoked_devices_token_closes_4001(active_user, device):
    access = await mint_access(active_user, device)
    await database_sync_to_async(
        type(device).objects.filter(id=device.id).update)(
            revoked_date=timezone.now().date())

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_stale_token_generation_closes_4001(active_user, device):
    """Bumping token_generation (the revoke cascade, §A8) invalidates every
    outstanding token immediately — including on the socket."""
    access = await mint_access(active_user, device)
    await database_sync_to_async(
        type(device).objects.filter(id=device.id).update)(token_generation=2)

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_inactive_users_token_closes_4001(active_user, device):
    access = await mint_access(active_user, device)
    await database_sync_to_async(
        type(active_user).objects.filter(id=active_user.id).update)(is_active=False)

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_unauthed_socket_sending_any_other_frame_closes_4001(db):
    comm = await connect_ok([])
    await comm.send_json_to({"type": "signal", "to_device": "x", "blob": "y"})
    await expect_close(comm, 4001)
    assert get_channel_layer().groups == {}


async def test_missing_token_closes_4001_at_the_deadline(db, monkeypatch):
    monkeypatch.setattr("realtime.consumers.AUTH_DEADLINE_SECONDS", 0.05)
    comm = await connect_ok([])
    await expect_close(comm, 4001)


# ---- origin allowlist (§A6) -------------------------------------------------

async def test_unlisted_origin_closes_4403_even_with_a_valid_token(active_user, device):
    access = await mint_access(active_user, device)
    comm = ws(bearer(access) + [(b"origin", b"https://evil.example")])
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4403)


async def test_allowlisted_origin_connects(active_user, device):
    access = await mint_access(active_user, device)
    comm = await connect_ok(bearer(access) + [(b"origin", b"http://localhost")])
    await comm.disconnect()


async def test_absent_origin_is_a_native_client_and_connects(active_user, device):
    """Dart's WebSocket sends no Origin. The header is a browser-only CSWSH defense —
    browsers always attach it — so its absence must not lock out the primary client."""
    access = await mint_access(active_user, device)
    comm = await connect_ok(bearer(access))  # no Origin header at all
    await comm.disconnect()


async def test_empty_allowlist_admits_any_origin(active_user, device, settings):
    settings.ALLOWED_WS_ORIGINS = []
    access = await mint_access(active_user, device)
    comm = await connect_ok(bearer(access) + [(b"origin", b"https://anything.example")])
    await comm.disconnect()
