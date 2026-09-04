"""The accounts routes: registration, login, the token lifecycle, the user
directory and the encrypted profile blobs.

Two routers, and a route belongs to exactly one of them. `anonymous` declares
that a route takes no credential; `authenticated` declares the default, which is
a full-scope token bound to a live device. A route on neither is a failed gate,
and `core/tests/test_route_table.py` is where it fails.
"""

import uuid

from fastapi import APIRouter, Depends, Response, status

from accounts import services
from accounts.schemas import (
    DirectoryOut,
    LoginIn,
    ProfileIn,
    ProfileOut,
    RefreshIn,
    RegisterIn,
    RegisterOut,
    TokenPairOut,
)
from api.auth import Principal, allow_anonymous, decode_refresh, require_full_device
from api.errors import TOKEN_REVOKED, ApiError
from api.orm import run_unit
from api.ratelimit import rate_limit

anonymous = APIRouter(tags=["accounts"], dependencies=[Depends(allow_anonymous)])
authenticated = APIRouter(tags=["accounts"], dependencies=[Depends(require_full_device)])


@anonymous.post(
    "/auth/register",
    response_model=RegisterOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("register"))],
)
async def register(payload: RegisterIn):
    return await run_unit(services.register, payload.username, payload.password)


@anonymous.post("/auth/login", dependencies=[Depends(rate_limit("login"))])
async def login(payload: LoginIn) -> dict:
    """Two success shapes: a full-scope pair when `device_id` names a live device
    of this account, and a register-scope token otherwise."""
    return await run_unit(
        services.login,
        payload.username.lower(),
        payload.password,
        payload.device_id,
    )


@anonymous.post(
    "/auth/refresh",
    response_model=TokenPairOut,
    dependencies=[Depends(rate_limit("refresh"))],
)
async def refresh(payload: RefreshIn):
    claims = decode_refresh(payload.refresh)
    pair = await run_unit(services.refresh, claims)
    if pair is None:
        raise ApiError(401, "token_revoked", TOKEN_REVOKED)
    return pair


@authenticated.post(
    "/auth/logout",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def logout(principal: Principal = Depends(require_full_device)):
    """Takes no body: the caller is identified by the access token it presents,
    and the device row is what carries the revocation. The presented token dies
    with the rest of the family, so a second call with it answers 401."""
    await run_unit(services.logout, principal.user.id, principal.device.id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@authenticated.get(
    "/users", response_model=DirectoryOut, dependencies=[Depends(rate_limit("accounts"))]
)
async def user_directory():
    return await run_unit(services.directory)


@authenticated.get(
    "/users/{user_id}/profile",
    response_model=ProfileOut,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def peer_profile(user_id: uuid.UUID):
    return await run_unit(services.peer_profile, user_id)


@authenticated.get(
    "/me/profile",
    response_model=ProfileOut,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def my_profile(principal: Principal = Depends(require_full_device)):
    return await run_unit(services.my_profile, principal.user.id)


@authenticated.put("/me/profile", dependencies=[Depends(rate_limit("accounts"))])
async def write_my_profile(
    payload: ProfileIn, principal: Principal = Depends(require_full_device)
):
    await run_unit(
        services.write_profile, principal.user.id, payload.raw, payload.version
    )
    return Response(status_code=status.HTTP_200_OK)
