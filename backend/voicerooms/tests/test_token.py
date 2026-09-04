"""LiveKit join tokens: short-lived, scoped to one room and one device, audio only,
and carrying no key material. The server mints; it never joins the media path."""

import time
import types
import uuid

import jwt
import pytest

from voicerooms.livekit import mint_join_token
from voicerooms.models import Room

from .conftest import LIVEKIT_SECRET as SECRET
from .conftest import LIVEKIT_URL, ROOMS_URL, envelope

# transaction=True because the route runs its unit of work through the ORM bracket
# of `api.orm.run_unit`, which closes the connection a wrapping test transaction
# would need.
pytestmark = pytest.mark.django_db(transaction=True)

# Emptying any one of these is what an unconfigured deployment looks like, and
# each has to answer the same refusal on its own.
VOICE_SETTINGS = ["LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]


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


@pytest.mark.parametrize("name", VOICE_SETTINGS)
def test_any_one_missing_livekit_setting_is_the_documented_503(
    http, active_user, device, bearer, room, voice_settings, name
):
    """Each of the three on its own, because a check written as one truthiness
    test over a tuple would pass this file while letting a half-configured
    deployment mint a grant nothing can verify."""
    setattr(voice_settings, name, "")

    response = http.post(
        f"{ROOMS_URL}/{room.id}/token", headers=bearer(active_user, device)
    )

    assert response.status_code == 503
    assert (
        envelope(response, "voice_unconfigured")["detail"] == "Voice is not configured."
    )


@pytest.mark.parametrize("name", VOICE_SETTINGS)
def test_an_unknown_room_stays_a_404_however_voice_is_configured(
    http, active_user, device, bearer, voice_settings, name
):
    """The room is checked before the configuration, so asking about a room that
    does not exist can never tell a client whether voice is configured — the
    answer is the same 404 either way."""
    setattr(voice_settings, name, "")

    response = http.post(
        f"{ROOMS_URL}/{uuid.uuid4()}/token", headers=bearer(active_user, device)
    )

    assert response.status_code == 404
    assert envelope(response, "not_found")["detail"] == "No such room."


@pytest.mark.parametrize("name", VOICE_SETTINGS)
def test_a_malformed_room_id_is_refused_before_either_check(
    http, active_user, device, bearer, voice_settings, name
):
    """And ahead of both: a path segment that is not a UUID never reaches the
    room lookup, so it cannot reveal the configuration either."""
    setattr(voice_settings, name, "")

    response = http.post(
        f"{ROOMS_URL}/not-a-uuid/token", headers=bearer(active_user, device)
    )

    assert response.status_code == 400
    assert set(envelope(response, "invalid_request")["detail"]) == {"room_id"}


def test_the_minted_token_verifies_under_the_configured_secret_and_no_other(
    http, active_user, device, bearer, room, voice_settings
):
    """The end-to-end signature check: what the route hands the client is what the
    SFU will accept, and rotating the secret is what stops accepting it."""
    body = http.post(
        f"{ROOMS_URL}/{room.id}/token", headers=bearer(active_user, device)
    ).json()

    assert jwt.decode(body["token"], SECRET, algorithms=["HS256"])["video"][
        "room"
    ] == str(room.id)
    with pytest.raises(jwt.InvalidSignatureError):
        jwt.decode(
            body["token"],
            "another-infrastructure-secret-of-real-length",
            algorithms=["HS256"],
        )


def test_the_url_the_client_is_sent_to_is_the_configured_one(
    http, active_user, device, bearer, room, voice_settings
):
    """The client dials the URL this answer carries, so it comes from the setting
    and not from the request's own `Host`."""
    body = http.post(
        f"{ROOMS_URL}/{room.id}/token", headers=bearer(active_user, device)
    ).json()

    assert body["url"] == LIVEKIT_URL


def test_the_advertised_lifetime_matches_the_lifetime_in_the_grant(
    http, active_user, device, bearer, room, voice_settings
):
    """`expires_in` is what a client schedules its re-mint on, so it must be the
    same number the signature enforces, not a second one that could drift."""
    voice_settings.LIVEKIT_TOKEN_TTL_SECONDS = 45
    before = int(time.time())

    body = http.post(
        f"{ROOMS_URL}/{room.id}/token", headers=bearer(active_user, device)
    ).json()

    after = int(time.time())
    claims = jwt.decode(body["token"], SECRET, algorithms=["HS256"])
    assert body["expires_in"] == 45
    assert claims["exp"] - claims["iat"] == 45
    assert claims["nbf"] == claims["iat"]
    assert before <= claims["iat"] <= after  # usable the instant it is issued


def test_a_second_mint_signs_a_fresh_grant_without_disturbing_the_first(
    http, active_user, device, bearer, room, voice_settings
):
    """The documented retry semantics: minting writes nothing, and the previous
    token stays valid until its own expiry passes."""
    url = f"{ROOMS_URL}/{room.id}/token"
    headers = bearer(active_user, device)

    first = http.post(url, headers=headers).json()["token"]
    second = http.post(url, headers=headers).json()["token"]

    for token in (first, second):
        assert jwt.decode(token, SECRET, algorithms=["HS256"])["sub"] == str(device.id)


def test_the_grant_names_the_room_that_was_asked_for_and_not_another(
    http, active_user, device, bearer, room, voice_settings
):
    """The boundary a wrong-row lookup would cross: with two rooms in the table,
    the grant still names the one in the path."""
    other = Room.objects.create(name_blob=b"o" * 256)

    body = http.post(
        f"{ROOMS_URL}/{room.id}/token", headers=bearer(active_user, device)
    ).json()

    claims = jwt.decode(body["token"], SECRET, algorithms=["HS256"])
    assert claims["video"]["room"] == str(room.id)
    assert claims["video"]["room"] != str(other.id)
