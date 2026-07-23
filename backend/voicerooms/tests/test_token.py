"""LiveKit join tokens: short-lived, scoped to one room and one device, audio only,
and carrying no key material. The server mints; it never joins the media path."""
import time
import types
import uuid

import jwt
import pytest
from rest_framework.test import APIRequestFactory, force_authenticate
from rest_framework.throttling import ScopedRateThrottle

from voicerooms.livekit import mint_join_token
from voicerooms.views import RoomTokenView

pytestmark = pytest.mark.django_db

SECRET = "lk-test-secret-well-over-thirty-two-bytes-long"


@pytest.fixture
def voice_settings(settings):
    settings.LIVEKIT_URL = "wss://voice.test"
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET
    settings.LIVEKIT_TOKEN_TTL_SECONDS = 300
    return settings


def test_token_endpoint_mints_a_room_and_device_scoped_audio_grant(
        api, active_user, device, auth_headers, room, voice_settings):
    resp = api.post(f"/api/v1/rooms/{room.id}/token",
                    **auth_headers(active_user, device))

    assert resp.status_code == 200
    assert set(resp.data) == {"url", "token", "expires_in"}
    assert resp.data["url"] == "wss://voice.test"
    assert resp.data["expires_in"] == 300

    claims = jwt.decode(resp.data["token"], SECRET, algorithms=["HS256"])
    assert set(claims) == {"iss", "sub", "nbf", "iat", "exp", "video"}
    assert claims["iss"] == "lk-test-key"
    assert claims["sub"] == str(device.id)          # identity = exactly this device
    assert claims["exp"] - claims["iat"] == 300     # TTL from settings, nothing longer
    assert claims["video"] == {
        "roomJoin": True,
        "room": str(room.id),                       # exactly this room
        "canPublish": True,
        "canSubscribe": True,
        "canPublishData": False,                    # room text rides the WS, not the SFU
        "canPublishSources": ["microphone"],        # publish audio only
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
        api, active_user, device, auth_headers, room, settings):
    settings.LIVEKIT_URL = ""
    settings.LIVEKIT_API_KEY = "lk-test-key"
    settings.LIVEKIT_API_SECRET = SECRET

    resp = api.post(f"/api/v1/rooms/{room.id}/token",
                    **auth_headers(active_user, device))

    assert resp.status_code == 503
    assert resp.data["code"] == "voice_unconfigured"


def test_unknown_room_is_404_even_when_configured(api, active_user, device,
                                                  auth_headers, voice_settings):
    resp = api.post(f"/api/v1/rooms/{uuid.uuid4()}/token",
                    **auth_headers(active_user, device))
    assert resp.status_code == 404


def test_full_scope_without_a_device_binding_is_refused(active_user, room,
                                                        voice_settings):
    """Defense in depth behind IsFullScope: even a misauthenticated full-scope request
    with no bound device gets no token; the identity must be a device id."""
    request = APIRequestFactory().post(f"/api/v1/rooms/{room.id}/token")
    force_authenticate(request, user=active_user, token={"scope": "full"})

    resp = RoomTokenView.as_view()(request, room_id=room.id)

    assert resp.status_code == 403
    assert resp.data["code"] == "device_scope_required"


def test_roomtoken_throttle_scope_is_enforced(api, active_user, device, auth_headers,
                                              room, voice_settings, monkeypatch):
    monkeypatch.setitem(ScopedRateThrottle.THROTTLE_RATES, "roomtoken", "2/min")
    headers = auth_headers(active_user, device)
    url = f"/api/v1/rooms/{room.id}/token"

    assert api.post(url, **headers).status_code == 200
    assert api.post(url, **headers).status_code == 200
    assert api.post(url, **headers).status_code == 429
