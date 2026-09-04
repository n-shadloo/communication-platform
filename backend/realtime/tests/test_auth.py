"""The socket authenticates with REST's strength: full scope, live device, matching
token_generation, active user. A failed handshake joins no group."""

import asyncio

import pytest
from django.utils import timezone

from api.auth import issue_register_scope
from api.orm import run_unit
from realtime.bus import device_topic, get_subscriber

from .conftest import bearer, connect_ok, expect_close, mint_access, probe, ws

pytestmark = pytest.mark.django_db(transaction=True)


def no_topic_is_held():
    """The bus subscription registry of this worker is empty.

    The Redis-side twin of the old in-memory `channel_layer.groups == {}`: there is
    no inspectable registry on Redis, so what a refused handshake must leave behind
    is checked where the gateway actually keeps it. A socket that never bound
    subscribed to no device topic, and a socket that bound and then failed
    unsubscribed on its way out.
    """
    return get_subscriber()._sinks == {}


async def test_header_auth_path_connects(active_user, device):
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)
    await comm.disconnect()


async def test_first_frame_auth_path_connects(active_user, device):
    """Browsers can't set WS headers: connect bare, then authenticate in-band."""
    comm = await connect_ok([])
    await comm.send_json_to(
        {"type": "auth", "access": await mint_access(active_user, device)}
    )
    await probe(comm, device.id)
    await comm.disconnect()


async def test_connect_touches_last_active_date(active_user, device):
    assert device.last_active_date is None
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)

    refreshed = await run_unit(type(device).objects.get, id=device.id)
    assert refreshed.last_active_date == timezone.now().date()
    await comm.disconnect()


async def test_garbage_token_closes_4001(db):
    comm = ws(bearer("not-a-jwt"))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_refresh_token_is_not_an_access_token(active_user, device):
    """A refresh JWT is validly signed but has the wrong token_type; REST rejects it
    and so must the socket."""
    from api.auth import issue_full

    _access, refresh = await run_unit(issue_full, active_user, device)

    comm = ws(bearer(refresh))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_register_scope_token_closes_4001_and_joins_no_group(active_user):
    """`register` scope buys exactly one REST endpoint and no socket."""
    token = await run_unit(issue_register_scope, active_user)

    comm = ws(bearer(token))
    connected, code = await comm.connect(timeout=2)

    assert (connected, code) == (False, 4001)
    assert no_topic_is_held()


async def test_register_scope_with_device_claims_still_closes_4001(active_user, device):
    """Scope is enforced in its own right, not via the missing device claim: even a
    register-scope token carrying a live device's id and tgen opens no socket."""
    import uuid
    from datetime import datetime, timedelta, timezone

    import jwt
    from django.conf import settings

    def forge():
        issued = datetime.now(timezone.utc)
        return jwt.encode(
            {
                "user_id": str(active_user.id),
                "device_id": str(device.id),
                "tgen": device.token_generation,
                "scope": "register",
                "typ": "access",
                "jti": uuid.uuid4().hex,
                "iat": issued,
                "exp": issued + timedelta(minutes=10),
            },
            settings.JWT_SIGNING_KEY,
            algorithm=settings.JWT_ALGORITHM,
        )

    comm = ws(bearer(await run_unit(forge)))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_register_scope_token_via_auth_frame_closes_4001(active_user):
    token = await run_unit(issue_register_scope, active_user)
    comm = await connect_ok([])

    await comm.send_json_to({"type": "auth", "access": token})

    await expect_close(comm, 4001)
    assert no_topic_is_held()


async def test_revoked_devices_token_closes_4001(active_user, device):
    access = await mint_access(active_user, device)
    await run_unit(
        type(device).objects.filter(id=device.id).update,
        revoked_date=timezone.now().date(),
    )

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_stale_token_generation_closes_4001(active_user, device):
    """Bumping token_generation (the revoke cascade) invalidates every outstanding
    token immediately, including on the socket."""
    access = await mint_access(active_user, device)
    await run_unit(type(device).objects.filter(id=device.id).update, token_generation=2)

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_inactive_users_token_closes_4001(active_user, device):
    access = await mint_access(active_user, device)
    await run_unit(
        type(active_user).objects.filter(id=active_user.id).update, is_active=False
    )

    comm = ws(bearer(access))
    connected, code = await comm.connect(timeout=2)
    assert (connected, code) == (False, 4001)


async def test_unauthed_socket_sending_any_other_frame_closes_4001(db):
    comm = await connect_ok([])
    await comm.send_json_to({"type": "signal", "to_device": "x", "blob": "y"})
    await expect_close(comm, 4001)
    assert no_topic_is_held()


async def test_missing_token_closes_4001_at_the_deadline(db, monkeypatch):
    monkeypatch.setattr("realtime.gateway.AUTH_DEADLINE_SECONDS", 0.05)
    comm = await connect_ok([])
    await expect_close(comm, 4001)


async def test_the_deadline_leaves_a_socket_that_authenticated_in_time_alone(
    active_user, device, monkeypatch
):
    """The deadline bounds an unauthenticated socket and nothing else. A timer that
    fired regardless would close every browser connection half a second into its
    session, and the header path would never see it because it never arms one."""
    monkeypatch.setattr("realtime.gateway.AUTH_DEADLINE_SECONDS", 0.5)
    comm = await connect_ok([])

    await comm.send_json_to(
        {"type": "auth", "access": await mint_access(active_user, device)}
    )
    await probe(comm, device.id)  # barrier: the bind is complete
    await asyncio.sleep(0.6)  # past the deadline the socket armed at accept

    await probe(comm, device.id)
    await comm.disconnect()


async def test_a_header_that_is_not_a_bearer_token_leaves_the_socket_on_the_bare_path(
    db, monkeypatch
):
    """`Authorization` is parsed, not trusted: a header this gateway cannot read is
    no token at all, which is the state a browser connects in. Refusing the
    handshake instead would turn a proxy that rewrites the header into a client
    that can never connect, and treating it as authentication would open a socket
    on nothing."""
    monkeypatch.setattr("realtime.gateway.AUTH_DEADLINE_SECONDS", 0.05)

    for header in (b"Basic Zm9vOmJhcg==", b"Bearer", b"Bearer a b", b"   "):
        comm = await connect_ok([(b"authorization", header)])
        await expect_close(comm, 4001)  # accepted, then unauthenticated at the deadline


async def test_an_auth_frame_whose_access_is_not_a_string_closes_4001(db):
    """A JSON object where the token belongs reaches the verifier as something it
    cannot decode. It is refused the way a garbage token is, rather than raising
    inside the decoder with the value in the traceback."""
    comm = await connect_ok([])

    await comm.send_json_to({"type": "auth", "access": {"forged": True}})

    await expect_close(comm, 4001)
    assert no_topic_is_held()


async def test_an_auth_frame_with_no_access_field_closes_4001(db):
    comm = await connect_ok([])

    await comm.send_json_to({"type": "auth"})

    await expect_close(comm, 4001)
    assert no_topic_is_held()


async def test_a_second_auth_frame_on_a_bound_socket_is_ignored(active_user, device):
    """Once bound, `auth` is just another type the handler does not know, so it is
    dropped like any unknown frame. Re-binding would let one socket change the
    device it delivers for, mid-session, without the topic it holds changing."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))

    await comm.send_json_to(
        {"type": "auth", "access": await mint_access(active_user, device)}
    )

    await probe(comm, device.id)
    await comm.disconnect()


async def test_a_bind_takes_the_device_topic_and_a_disconnect_gives_it_back(
    active_user, device
):
    """The subscription is the socket's half of delivery, and it is per topic
    rather than a pattern: a topic left held after the socket is gone keeps this
    worker receiving a departed device's envelopes for the life of the process."""
    comm = await connect_ok(bearer(await mint_access(active_user, device)))
    await probe(comm, device.id)

    assert get_subscriber()._sinks.keys() == {device_topic(device.id)}

    await comm.disconnect()
    assert no_topic_is_held()


# ---- origin allowlist -------------------------------------------------------


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
    """Dart's WebSocket sends no Origin. The header is a browser-only CSWSH defense
    (browsers always attach it), so its absence must not lock out the primary
    client."""
    access = await mint_access(active_user, device)
    comm = await connect_ok(bearer(access))  # no Origin header at all
    await comm.disconnect()


async def test_empty_allowlist_admits_any_origin(active_user, device, settings):
    settings.ALLOWED_WS_ORIGINS = []
    access = await mint_access(active_user, device)
    comm = await connect_ok(bearer(access) + [(b"origin", b"https://anything.example")])
    await comm.disconnect()
