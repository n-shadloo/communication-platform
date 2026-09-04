"""The route table of the first surface, and the gate that keeps it closed.

FastAPI has no project-wide permission default the way REST Framework does, so a
route whose author forgot the dependency is public and nothing reports it. This
walks every route the application serves and asserts that each one carries
exactly the requirement the phase records, that the requirement is resolved
before the limiter that keys on it, and that the table holds nothing else.
"""

import pytest
from django.core.handlers.asgi import ASGIHandler
from fastapi.routing import iter_route_contexts

from api.auth import allow_anonymous, require_full_device, require_register_or_full
from config.asgi import api_application
from config.urls import ADMIN_PATH
from devices.routes import require_own_device

ANONYMOUS = allow_anonymous.__name__
FULL_DEVICE = require_full_device.__name__
REGISTER_OR_FULL = require_register_or_full.__name__
REQUIREMENTS = frozenset({ANONYMOUS, FULL_DEVICE, REGISTER_OR_FULL})

OWN_DEVICE = require_own_device.__name__

# (method, path) -> (authentication requirement, rate-limit scope or None).
# A route is closed by default: every entry is FULL_DEVICE unless it is one of
# the routes the phase records as declaring otherwise.
EXPECTED = {
    ("GET", "/api/v1/health"): (ANONYMOUS, None),
    ("POST", "/api/v1/auth/register"): (ANONYMOUS, "register"),
    ("POST", "/api/v1/auth/login"): (ANONYMOUS, "login"),
    ("POST", "/api/v1/auth/refresh"): (ANONYMOUS, "refresh"),
    ("POST", "/api/v1/auth/logout"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/users"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/users/{user_id}/profile"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/me/profile"): (FULL_DEVICE, "accounts"),
    ("PUT", "/api/v1/me/profile"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/me/keybackup"): (FULL_DEVICE, "accounts"),
    ("PUT", "/api/v1/me/keybackup"): (FULL_DEVICE, "accounts"),
    ("PUT", "/api/v1/me/identity"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/users/{user_id}/identity"): (FULL_DEVICE, "accounts"),
    # Registration is the one route a register-scope token reaches, and it is a
    # per-method opt-down: the device list on the same path stays full scope.
    ("POST", "/api/v1/me/devices"): (REGISTER_OR_FULL, "accounts"),
    ("GET", "/api/v1/me/devices"): (FULL_DEVICE, "accounts"),
    ("PUT", "/api/v1/me/devices/{device_id}"): (FULL_DEVICE, "accounts"),
    ("DELETE", "/api/v1/me/devices/{device_id}"): (FULL_DEVICE, "accounts"),
    ("PUT", "/api/v1/me/devices/{device_id}/prekeys"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/me/devices/{device_id}/prekeys/count"): (FULL_DEVICE, "accounts"),
    ("POST", "/api/v1/me/devicelog"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/users/{user_id}/devicelog"): (FULL_DEVICE, "accounts"),
    ("GET", "/api/v1/users/{user_id}/devices"): (FULL_DEVICE, "accounts"),
    ("POST", "/api/v1/users/{user_id}/keys/claim"): (FULL_DEVICE, "claim"),
    ("POST", "/api/v1/envelopes"): (FULL_DEVICE, "envelopes"),
    ("GET", "/api/v1/me/envelopes"): (FULL_DEVICE, "envelopes"),
    ("POST", "/api/v1/me/envelopes/ack"): (FULL_DEVICE, "envelopes"),
}

# The routes whose path names a device the token itself must be. Recorded here
# rather than left to each handler, because a route that drops the gate reads
# exactly like one that never needed it.
OWN_DEVICE_ROUTES = frozenset(
    {
        ("PUT", "/api/v1/me/devices/{device_id}/prekeys"),
        ("GET", "/api/v1/me/devices/{device_id}/prekeys/count"),
    }
)

LIMITER_PREFIX = "rate_limit_"


def served():
    """(method, path) -> the names of the dependencies the route declares."""
    table = {}
    for context in iter_route_contexts(api_application.routes):
        names = [dep.call.__name__ for dep in context.dependant.dependencies]
        for method in context.methods:
            table[(method, context.path)] = names
    return table


def test_the_route_table_is_exactly_the_declared_one():
    assert set(served()) == set(EXPECTED)


@pytest.mark.parametrize("route", sorted(EXPECTED))
def test_every_route_declares_exactly_one_authentication_requirement(route):
    declared = {name for name in served()[route] if name in REQUIREMENTS}

    assert declared == {EXPECTED[route][0]}, route


@pytest.mark.parametrize("route", sorted(EXPECTED))
def test_every_route_counts_against_its_declared_scope(route):
    scopes = [
        name.removeprefix(LIMITER_PREFIX)
        for name in served()[route]
        if name.startswith(LIMITER_PREFIX)
    ]
    expected = EXPECTED[route][1]

    assert scopes == ([] if expected is None else [expected]), route


@pytest.mark.parametrize(
    "route", sorted(key for key, value in EXPECTED.items() if value[1] is not None)
)
def test_the_requirement_is_resolved_before_the_limiter(route):
    """The limiter keys an authenticated request on the account, which it can only
    read once the requirement has put the principal on the request."""
    names = served()[route]
    limiter = next(i for i, name in enumerate(names) if name.startswith(LIMITER_PREFIX))
    requirement = next(i for i, name in enumerate(names) if name in REQUIREMENTS)

    assert requirement < limiter, route


@pytest.mark.parametrize("route", sorted(EXPECTED))
def test_only_the_recorded_routes_gate_on_the_calling_device(route):
    """The own-device gate is an authorization dependency on top of the
    requirement, not a replacement for it: a route that carries it must still
    declare that it needs a full-scope token."""
    gated = OWN_DEVICE in served()[route]

    assert gated == (route in OWN_DEVICE_ROUTES), route


def test_only_the_recorded_routes_are_open():
    anonymous = {route for route, names in served().items() if ANONYMOUS in names}

    assert anonymous == {
        route for route, (kind, _scope) in EXPECTED.items() if kind == ANONYMOUS
    }


def test_the_django_application_answers_only_what_no_route_claims():
    """It is the router's `default`, not a mount: a mount at "/" matches every
    path and would answer before the wrong-method refusal of a moved route."""
    assert isinstance(api_application.router.default, ASGIHandler)
    assert not any(
        route.path == "/" for route in api_application.routes if hasattr(route, "path")
    )


def test_a_trailing_slash_is_never_a_redirect():
    """The redirect rebuilds an absolute address from the scope path and drops any
    prefix a proxy stripped, which turns a write into a lost request."""
    assert api_application.router.redirect_slashes is False


@pytest.mark.django_db(transaction=True)
def test_the_django_application_still_answers_its_own_paths(http):
    """The admin and the routes that have not moved are reached through the
    catch-all, so the transition topology is what this asserts, not Django alone."""
    admin = http.get(f"/{ADMIN_PATH}")
    assert admin.status_code == 302
    assert "login" in admin.headers["location"]

    unmoved = http.get("/api/v1/rooms")
    assert unmoved.status_code == 401
    assert unmoved.json()["code"] == "unauthenticated"


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
def test_the_schema_and_its_documentation_are_closed(http, path):
    """The document lists every route, every model and every parameter of a server
    whose posture is to reveal nothing."""
    assert http.get(path).status_code == 404
