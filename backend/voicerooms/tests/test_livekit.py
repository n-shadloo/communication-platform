"""The grant `voicerooms/livekit.py` signs, read back with the same library the
SFU verifies it with.

The server's whole part in a voice call is this function: it signs a short-lived
statement that one device may join one room and speak, hands it to that device,
and never touches the media path again. So the properties that matter are what
the statement says (one room, one device, microphone only, no data channel), how
long it says it for, and what it does *not* carry — the media key is generated on
the client, distributed over pairwise sessions, and has no server-side existence
to leak into a claim.

`voicerooms/tests/test_token.py` drives the same grant through the route, where
the configuration refusal and the rate limit live.
"""

import time
import types
import uuid

import jwt
import pytest

from voicerooms.livekit import mint_join_token

from .conftest import LIVEKIT_API_KEY, LIVEKIT_SECRET

# `mint_join_token` reads no row, so nothing here needs a database.
GRANT_CLAIMS = {"iss", "sub", "nbf", "iat", "exp", "video"}
VIDEO_CLAIMS = {
    "roomJoin",
    "room",
    "canPublish",
    "canSubscribe",
    "canPublishData",
    "canPublishSources",
}


@pytest.fixture
def frozen_clock(monkeypatch):
    """One instant for the whole mint, so `nbf`, `iat` and `exp` can be asserted
    as exact numbers rather than as a window.

    Taken from the real clock rather than written out: PyJWT refuses a token whose
    `iat` is in the future and one whose `exp` is in the past, so a fixed literal
    would verify only on the day it was chosen.
    """
    instant = int(time.time())
    monkeypatch.setattr(
        "voicerooms.livekit.time", types.SimpleNamespace(time=lambda: instant)
    )
    return instant


def decode(token, secret=LIVEKIT_SECRET, **kwargs):
    return jwt.decode(token, secret, algorithms=["HS256"], **kwargs)


def test_the_token_verifies_under_the_livekit_api_secret_and_says_hs256(voice_settings):
    """The normal path, stated as the SFU sees it: the same shared secret, the
    same algorithm, and a signature that checks out."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    assert jwt.get_unverified_header(token)["alg"] == "HS256"
    assert set(decode(token)) == GRANT_CLAIMS


def test_the_grant_names_exactly_this_room_and_exactly_this_device(voice_settings):
    room_id, device_id = uuid.uuid4(), uuid.uuid4()

    token, _ttl = mint_join_token(room_id, device_id)

    claims = decode(token)
    assert claims["iss"] == LIVEKIT_API_KEY
    assert claims["sub"] == str(device_id)  # the LiveKit identity is the device
    assert claims["video"]["room"] == str(room_id)
    assert claims["video"]["roomJoin"] is True


def test_the_grant_allows_the_microphone_and_forbids_the_data_channel(voice_settings):
    """Audio only, and no data: ephemeral room text rides the WebSocket group, so
    a client that could publish data through the SFU would have a second, unaudited
    path for room content."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    video = decode(token)["video"]
    assert set(video) == VIDEO_CLAIMS
    assert video["canPublish"] is True
    assert video["canSubscribe"] is True
    assert video["canPublishData"] is False
    assert video["canPublishSources"] == ["microphone"]


def test_the_token_starts_now_and_expires_after_the_configured_ttl(
    voice_settings, frozen_clock
):
    """`nbf` and `iat` at the issue instant, `exp` a TTL later. A `nbf` in the
    future would make a freshly minted token unusable for that long."""
    voice_settings.LIVEKIT_TOKEN_TTL_SECONDS = 300

    token, ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    claims = decode(token)
    assert ttl == 300
    assert claims["nbf"] == frozen_clock
    assert claims["iat"] == frozen_clock
    assert claims["exp"] == frozen_clock + 300


@pytest.mark.parametrize("configured", [1, 30, 3600])
def test_the_ttl_setting_is_the_only_thing_that_sets_the_lifetime(
    voice_settings, frozen_clock, configured
):
    """The boundary in both directions: a one-second grant and an hour-long one
    both come straight from the setting, with nothing clamped or defaulted."""
    voice_settings.LIVEKIT_TOKEN_TTL_SECONDS = configured

    token, ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    claims = decode(token)
    assert ttl == configured
    assert claims["exp"] - claims["iat"] == configured


def test_a_grant_older_than_its_ttl_is_refused_by_the_same_verification(
    voice_settings, monkeypatch
):
    """The error path the short lifetime exists for: a leaked token stops working
    on its own, with no revocation list and no server-side session to end."""
    voice_settings.LIVEKIT_TOKEN_TTL_SECONDS = 300
    monkeypatch.setattr(
        "voicerooms.livekit.time",
        types.SimpleNamespace(time=lambda: time.time() - 300 - 60),
    )

    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    with pytest.raises(jwt.ExpiredSignatureError):
        decode(token)


def test_a_token_minted_under_a_rotated_secret_no_longer_verifies(voice_settings):
    """Rotating `LIVEKIT_API_SECRET` is the deployment's revocation, so a grant
    signed under the old one must fail the signature rather than the expiry."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    with pytest.raises(jwt.InvalidSignatureError):
        decode(token, secret="a-different-infrastructure-secret-of-real-length")


def test_a_grant_whose_room_was_edited_fails_the_signature(voice_settings):
    """Why the grant is signed at all: a client that rewrote the room claim to
    join a room it was never given the capability for is refused by the SFU."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())
    header, payload, signature = token.split(".")
    forged = mint_join_token(uuid.uuid4(), uuid.uuid4())[0].split(".")[1]

    with pytest.raises(jwt.InvalidSignatureError):
        decode(f"{header}.{forged}.{signature}")


def test_the_signing_secret_is_never_carried_in_the_token_it_signs(voice_settings):
    """A signature is not an envelope: the shared secret proves the grant and must
    not travel with it, in the payload or in the header."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    assert LIVEKIT_SECRET not in token
    assert LIVEKIT_SECRET not in str(decode(token))
    assert LIVEKIT_SECRET not in str(jwt.get_unverified_header(token))


def test_the_grant_carries_no_media_or_content_key_of_any_kind(voice_settings):
    """The invariant this whole app is shaped around: every key that decrypts room
    audio is client-side, so there is nothing here for a claim to hold. Asserted
    as an exact claim set, because an extra claim is the only way one could
    arrive."""
    token, _ttl = mint_join_token(uuid.uuid4(), uuid.uuid4())

    claims = decode(token)
    assert set(claims) == GRANT_CLAIMS
    assert set(claims["video"]) == VIDEO_CLAIMS
    # Nothing in the payload is bytes-shaped: the only strings are the issuer key
    # id, the two ids, and the source tag.
    assert {type(value) for value in claims.values()} == {str, int, dict}


def test_an_id_given_as_a_string_signs_the_same_grant_as_the_uuid(voice_settings):
    """The rare case at the seam: the route passes UUID objects and the WebSocket
    gateway passes strings, and a grant that differed between them would name a
    room LiveKit could not match."""
    room_id, device_id = uuid.uuid4(), uuid.uuid4()

    from_objects = decode(mint_join_token(room_id, device_id)[0])
    from_strings = decode(mint_join_token(str(room_id), str(device_id))[0])

    assert from_objects["video"]["room"] == from_strings["video"]["room"]
    assert from_objects["sub"] == from_strings["sub"]
