"""System-wide log-silence audit, driving ops/audit/log_silence.py.

The per-app suites spot-check their own paths; this pass runs one scripted sequence
across auth, devices, messaging, attachments, realtime, and voice, and asserts none
of the identifiers/blobs/tokens it generated reached any log line. The second test
proves the audit itself still has teeth, including against loggers that do not
propagate to root, the blind spot that would let a leak grade its own homework.
"""
import logging

import pytest

from ops.audit.log_silence import run_audit

pytestmark = pytest.mark.django_db(transaction=True)


@pytest.fixture(autouse=True)
def _isolated_runtime(settings, tmp_path):
    """Volatile stays volatile (in-memory layer), uploads stay out of the repo, and
    LiveKit minting gets fake infrastructure credentials (signing is local PyJWT)."""
    settings.CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}
    settings.ATTACHMENTS_ROOT = tmp_path
    settings.LIVEKIT_URL = "wss://livekit.audit.test"
    settings.LIVEKIT_API_KEY = "lk-audit-key"
    settings.LIVEKIT_API_SECRET = "lk-audit-secret-0123456789abcdef0123456789abcdef"


async def test_scripted_traffic_across_every_surface_leaks_nothing():
    leaks, secrets, _lines = await run_audit()

    assert leaks == [], f"identifiers/payloads reached the logs: {leaks}"
    # Anti-vacuity: every step really ran and generated its secret.
    for label in ("user id", "register-scope access token", "device id", "access token",
                  "refresh token", "envelope blob", "queued envelope id",
                  "attachment id", "room id", "livekit join token", "signal blob"):
        assert secrets.get(label), f"the audit never exercised the {label} step"


async def test_the_audit_catches_a_leak_even_on_a_non_propagating_logger():
    """django.request has its own handler and propagate=False, the spot assertLogs
    misses. A deliberate leak there must come back non-empty, or the audit is dead."""
    def leak(secrets):
        logging.getLogger("django.request").error(
            "device %s misbehaved", secrets["device id"])

    leaks, _secrets, _lines = await run_audit(probe=leak)

    assert any("device id" in leak_line for leak_line in leaks), \
        "a deliberately logged device id was not detected"
