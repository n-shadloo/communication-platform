"""System-wide log-silence audit, driving ops/audit/log_silence.py.

The per-app suites spot-check their own paths; this pass runs one scripted sequence
across auth, devices, messaging, attachments, realtime, and voice, and asserts none
of the identifiers/blobs/tokens it generated reached any log line. The second test
proves the audit itself still has teeth, including against loggers that do not
propagate to root, the blind spot that would let a leak grade its own homework. The
third holds the pass to the whole route table, because a route the audit never calls
is a route it never cleared.
"""

import logging

import pytest
from fastapi.routing import iter_route_contexts
from starlette.routing import compile_path

from config.asgi import api_application
from core.tests.test_route_table import EXPECTED
from ops.audit.log_silence import run_audit

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture(autouse=True)
def _isolated_runtime(settings, tmp_path):
    """Volatile stays volatile (in-memory layer), uploads stay out of the repo, and
    LiveKit minting gets fake infrastructure credentials (signing is local PyJWT)."""
    settings.CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}
    }
    settings.ATTACHMENTS_ROOT = tmp_path
    settings.LIVEKIT_URL = "wss://livekit.audit.test"
    settings.LIVEKIT_API_KEY = "lk-audit-key"
    settings.LIVEKIT_API_SECRET = "lk-audit-secret-0123456789abcdef0123456789abcdef"


def matchers():
    """(method, compiled path, path template) for every route the API serves.

    Compiled from the templates rather than matched through the router, because a
    router included under a prefix is not itself a route with a path.
    """
    for context in iter_route_contexts(api_application.routes):
        regex, _format, _convertors = compile_path(context.path)
        for method in context.methods:
            yield method, regex, context.path


MATCHERS = list(matchers())


def route_of(method, path):
    """The route-table entry a recorded request landed on, or None for a path this
    API serves through the Django application."""
    for candidate, regex, template in MATCHERS:
        if candidate == method and regex.match(path):
            return (method, template)
    return None


async def test_scripted_traffic_across_every_surface_leaks_nothing():
    leaks, secrets, _lines, _requested = await run_audit()

    assert leaks == [], f"identifiers/payloads reached the logs: {leaks}"
    # Anti-vacuity: every step really ran and generated its secret.
    for label in (
        "user id",
        "register-scope access token",
        "device id",
        "access token",
        "refresh token",
        "envelope blob",
        "queued envelope id",
        "attachment id",
        "room id",
        "livekit join token",
        "signal blob",
        "profile blob",
        "key backup blob",
        "rotated access token",
        "rotated refresh token",
    ):
        assert secrets.get(label), f"the audit never exercised the {label} step"


async def test_the_audit_catches_a_leak_even_on_a_non_propagating_logger():
    """django.request has its own handler and propagate=False, the spot assertLogs
    misses. A deliberate leak there must come back non-empty, or the audit is dead."""

    def leak(secrets):
        logging.getLogger("django.request").error(
            "device %s misbehaved", secrets["device id"]
        )

    leaks, _secrets, _lines, _requested = await run_audit(probe=leak)

    assert any("device id" in leak_line for leak_line in leaks), (
        "a deliberately logged device id was not detected"
    )


async def test_the_pass_drives_every_route_of_the_table():
    """A route the audit never calls is a route it never cleared, and a route added
    to the table without a step here would be cleared by silence."""
    _leaks, _secrets, _lines, requested = await run_audit()

    driven = {route_of(method, path) for method, path in requested}

    assert driven - {None} == set(EXPECTED)
