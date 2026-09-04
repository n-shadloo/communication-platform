"""LiveKit join tokens: short-lived, scoped to one room and one device, audio only,
and carrying no key material. The server mints; it never joins the media path."""

import time
import types
import uuid

import jwt
import pytest

from voicerooms.livekit import mint_join_token

# transaction=True because the route runs its unit of work through the ORM bracket
# of `api.orm.run_unit`, which closes the connection a wrapping test transaction
# would need.
pytestmark = pytest.mark.django_db(transaction=True)

SECRET = "lk-test-secret-well-over-thirty-two-bytes-long"


@pytest.fixture
def voice_settings(settings):
    settings.LIVEKIT_URL = "wss://voice.test"
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET
    settings.LIVEKIT_TOKEN_TTL_SECONDS = 300
    return settings


def test_token_endpoint_mints_a_room_and_device_scoped_audio_grant(
    http, active_user, device, bearer, room, voice_settings
):
    resp = http.post(
        f"/api/v1/rooms/{room.id}/token", headers=bearer(active_user, device)
    )

    assert resp.status_code == 200
    body = resp.json()
    assert set(body) == {"url", "token", "expires_in"}
    assert body["url"] == "wss://voice.test"
    assert body["expires_in"] == 300

    claims = jwt.decode(body["token"], SECRET, algorithms=["HS256"])
    assert set(claims) == {"iss", "sub", "nbf", "iat", "exp", "video"}
    assert claims["iss"] == "lk-test-key"
    assert claims["sub"] == str(device.id)  # identity = exactly this device
    assert claims["exp"] - claims["iat"] == 300  # TTL from settings, nothing longer
    assert claims["video"] == {
        "roomJoin": True,
        "room": str(room.id),  # exactly this room
        "canPublish": True,
        "canSubscribe": True,
        "canPublishData": False,  # room text rides the WS, not the SFU
        "canPublishSources": ["microphone"],  # publish audio only
    }


def test_ttl_setting_drives_the_expiry(voice_settings):
    voice_settings.LIVEKIT_TOKEN_TTL_SECONDS = 7

    token, ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    assert ttl == 7
    claims = jwt.decode(token, SECRET, algorithms=["HS256"])
    assert claims["exp"] - claims["iat"] == 7


def test_an_expired_token_fails_verification(voice_settings, monkeypatch):
    """End-to-end expiry: a token minted TTL+60s in the past is refused by the same
    HS256 verification the SFU performs."""
    past = types.SimpleNamespace(time=lambda: time.time() - 300 - 60)
    monkeypatch.setattr("voicerooms.livekit.time", past)
    token, _ = mint_join_token(uuid.uuid4(), uuid.uuid4())

    with pytest.raises(jwt.ExpiredSignatureError):
        jwt.decode(token, SECRET, algorithms=["HS256"])


def test_unconfigured_livekit_is_a_503_not_a_broken_token(
    http, active_user, device, bearer, room, settings
):
    settings.LIVEKIT_URL = ""
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET

    resp = http.post(
        f"/api/v1/rooms/{room.id}/token", headers=bearer(active_user, device)
    )

    assert resp.status_code == 503
    assert resp.json()["code"] == "voice_unconfigured"


def test_unknown_room_is_404_even_when_configured(
    http, active_user, device, bearer, voice_settings
):
    """The room is checked before the configuration, so a client cannot learn
    whether voice is configured by asking about a room that does not exist."""
    resp = http.post(
        f"/api/v1/rooms/{uuid.uuid4()}/token", headers=bearer(active_user, device)
    )

    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


def test_the_mint_counts_against_its_own_scope(
    http, active_user, device, bearer, room, voice_settings, settings
):
    """Tighter than the room CRUD it sits beside: minting is the one room route
    that signs something."""
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "roomtoken": "2/min"}
    headers = bearer(active_user, device)
    url = f"/api/v1/rooms/{room.id}/token"

    assert http.post(url, headers=headers).status_code == 200
    assert http.post(url, headers=headers).status_code == 200
    assert http.post(url, headers=headers).status_code == 429

    # The CRUD scope is untouched by the exhausted mint scope.
    assert http.get(f"/api/v1/rooms/{room.id}", headers=headers).status_code == 200
