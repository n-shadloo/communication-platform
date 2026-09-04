import base64

import pytest

from core.buckets import NAME_BUCKETS
from voicerooms.models import Room

NAME_LEN = min(NAME_BUCKETS)

ROOMS_URL = "/api/v1/rooms"

# A loopback port nothing listens on. An injected Redis outage refuses the
# connection immediately, so a failure-injection test costs no wall clock.
DEAD_REDIS_URL = "redis://127.0.0.1:6390"

# Over 32 bytes, so signing an HS256 grant raises no key-length warning.
LIVEKIT_SECRET = "lk-test-secret-well-over-thirty-two-bytes-long"
LIVEKIT_URL = "wss://voice.test"
LIVEKIT_API_KEY = "lk-test-key"
LIVEKIT_TTL = 300


def name_blob_b64(fill=b"n", length=NAME_LEN):
    """A base64 name blob of exactly one NAME bucket; the client does the padding."""
    return base64.b64encode(fill * length).decode()


def envelope(response, code):
    """The error body, asserted to be exactly the two keys `core/API.md` publishes.

    Returned so a caller can go on to assert what `detail` names, which for
    `invalid_request` is a field path and for everything else is a fixed string.
    """
    body = response.json()
    assert set(body) == {"code", "detail"}, body
    assert body["code"] == code, body
    return body


@pytest.fixture
def room(db):
    return Room.objects.create(name_blob=b"n" * NAME_LEN)


@pytest.fixture
def voice_settings(settings):
    """LiveKit configured, so a mint reaches the signing step rather than the
    `503` the unconfigured deployment answers."""
    settings.LIVEKIT_URL = LIVEKIT_URL
    settings.LIVEKIT_API_KEY = LIVEKIT_API_KEY
    settings.LIVEKIT_API_SECRET = LIVEKIT_SECRET
    settings.LIVEKIT_TOKEN_TTL_SECONDS = LIVEKIT_TTL
    return settings
