"""Token issue, token verification, and the authentication dependencies.

This module is the only issuer and the only verifier of a token in the system.
The FastAPI dependencies below, `accounts.auth` for the routes that still run on
REST Framework, and `realtime.auth` for the WebSocket gateway all reach the same
two functions, so a token one stack revokes is dead on the other.

No token is ever stored. A refresh is rotation plus reuse detection over two
counters on the device row: `token_generation` kills every token of the device,
and `refresh_generation` kills every refresh token issued before the last one.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import jwt
from django.conf import settings
from fastapi import Request

from accounts.models import User
from api.errors import (
    INVALID_TOKEN,
    SCOPE_FORBIDDEN,
    TOKEN_REVOKED,
    UNAUTHENTICATED,
    ApiError,
)
from api.orm import run_unit
from devices.models import Device

ACCESS = "access"
REFRESH = "refresh"
FULL = "full"
REGISTER = "register"

# Every decode requires these. The library skips a check on an absent claim, so
# the require list is what turns a missing claim into a failure instead of a
# silently passed check.
_REQUIRED = ["exp", "iat", "jti", "typ", "scope", "user_id"]


@dataclass(frozen=True)
class Principal:
    """The caller of a route, after the token verified and the row was read."""

    user: object
    device: object
    claims: dict


def _now():
    return datetime.now(timezone.utc)


def _encode(claims):
    return jwt.encode(claims, settings.JWT_SIGNING_KEY, algorithm=settings.JWT_ALGORITHM)


def _claims(user_id, scope, typ, lifetime):
    issued = _now()
    return {
        "user_id": str(user_id),
        "scope": scope,
        "typ": typ,
        "jti": uuid.uuid4().hex,
        "iat": issued,
        "exp": issued + lifetime,
    }


def issue_full(user, device):
    """The access/refresh pair bound to one device, at its current generations."""
    access = _claims(
        user.id, FULL, ACCESS, timedelta(minutes=settings.ACCESS_TOKEN_MINUTES)
    )
    access["device_id"] = str(device.id)
    access["tgen"] = device.token_generation
    refresh = _claims(user.id, FULL, REFRESH, timedelta(days=settings.REFRESH_TOKEN_DAYS))
    refresh["device_id"] = str(device.id)
    refresh["tgen"] = device.token_generation
    refresh["rgen"] = device.refresh_generation
    return _encode(access), _encode(refresh)


def issue_register_scope(user):
    """The short-lived token whose only power is adding a device."""
    return _encode(
        _claims(
            user.id,
            REGISTER,
            ACCESS,
            timedelta(minutes=settings.REGISTER_SCOPE_ACCESS_MIN),
        )
    )


def _invalid_token():
    return ApiError(401, "invalid_token", INVALID_TOKEN)


def _decode(raw, typ):
    """Verify a token and return its claims. No I/O happens here.

    Pinning `algorithms` is what stops an `alg: none` token and an
    algorithm-confusion token; checking `typ` is what stops a refresh token
    presented as an access token.
    """
    if not isinstance(raw, str):
        raise _invalid_token()
    try:
        claims = jwt.decode(
            raw,
            settings.JWT_SIGNING_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"require": _REQUIRED},
        )
    except jwt.PyJWTError:
        raise _invalid_token()
    if claims["typ"] != typ or claims["scope"] not in (FULL, REGISTER):
        raise _invalid_token()
    return claims


def _device_bound(claims):
    """Every full-scope token names a device and the generation it was cut at."""
    try:
        uuid.UUID(str(claims["device_id"]))
    except (KeyError, TypeError, ValueError):
        raise _invalid_token()
    if not isinstance(claims.get("tgen"), int):
        raise _invalid_token()
    return claims


def decode_access(raw):
    claims = _decode(raw, ACCESS)
    if claims["scope"] == FULL:
        _device_bound(claims)
    return claims


def decode_refresh(raw):
    """A refresh token is always full scope: a register-scope token must never
    rotate its way up to a device-bound pair."""
    claims = _decode(raw, REFRESH)
    if claims["scope"] != FULL:
        raise _invalid_token()
    _device_bound(claims)
    if not isinstance(claims.get("rgen"), int):
        raise _invalid_token()
    return claims


def load_device(claims):
    """One query for the device row and its owner's activation state.

    Returns None when the device is gone, revoked, cut at an older token
    generation, or owned by an account the operator deactivated. The caller
    reports all four identically: the client learns only that this token is
    finished.

    `queue_pruned_through` rides along so the envelope drain can report it
    without a second device query.
    """
    device = (
        Device.objects.select_related("user")
        .only(
            "id",
            "user_id",
            "token_generation",
            "revoked_date",
            "queue_pruned_through",
            "user__is_active",
        )
        .filter(
            id=claims["device_id"],
            user_id=claims["user_id"],
            revoked_date__isnull=True,
        )
        .first()
    )
    if device is None or device.token_generation != claims["tgen"]:
        return None
    if not device.user.is_active:
        return None
    return device


def load_register_user(claims):
    """The owner of a register-scope token, or None when the account is gone or
    the operator deactivated it. A register token names no device, so the two
    device generations have nothing to check here."""
    return User.objects.filter(id=claims["user_id"], is_active=True).only("id").first()


def bearer(request):
    """The token of an `Authorization: Bearer` header, or a 401."""
    header = request.headers.get("authorization")
    if header is None:
        raise ApiError(
            401, "unauthenticated", UNAUTHENTICATED, {"WWW-Authenticate": "Bearer"}
        )
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise ApiError(
            401, "unauthenticated", UNAUTHENTICATED, {"WWW-Authenticate": "Bearer"}
        )
    return token.strip()


async def require_full_device(request: Request) -> Principal:
    """The default requirement of every route: a full-scope, device-bound token
    whose device is live and whose account is active."""
    claims = decode_access(bearer(request))
    if claims["scope"] != FULL:
        raise ApiError(403, "scope_forbidden", SCOPE_FORBIDDEN)
    device = await run_unit(load_device, claims)
    if device is None:
        raise ApiError(401, "token_revoked", TOKEN_REVOKED)
    principal = Principal(user=device.user, device=device, claims=claims)
    request.state.principal = principal
    return principal


async def require_register_or_full(request: Request) -> Principal:
    """The requirement of device registration, and of nothing else.

    A register-scope token names no device, so the principal it builds carries
    none; the route it reaches is the one that mints the device the caller lacks.
    Every other route takes `require_full_device`, which refuses that token.
    """
    claims = decode_access(bearer(request))
    if claims["scope"] == FULL:
        device = await run_unit(load_device, claims)
        if device is None:
            raise ApiError(401, "token_revoked", TOKEN_REVOKED)
        principal = Principal(user=device.user, device=device, claims=claims)
    else:
        user = await run_unit(load_register_user, claims)
        if user is None:
            raise ApiError(401, "token_revoked", TOKEN_REVOKED)
        principal = Principal(user=user, device=None, claims=claims)
    request.state.principal = principal
    return principal


async def allow_anonymous(request: Request) -> None:
    """The declared requirement of a route that takes no credential. A route
    declares this or `require_full_device`; a route that declares neither is a
    failed gate, and `core/tests/test_route_table.py` is where it fails."""
    request.state.principal = None
