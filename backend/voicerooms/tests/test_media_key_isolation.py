"""The §A9 headline invariant: **no media-key path exists on this server.**

No model field, no serializer field, and no token claim anywhere carries an SFrame /
media / room-content key, and the room join token is a pure LiveKit video grant. The
LiveKit API secret is *infrastructure* (§A12) and is deliberately not a match target.
"""
import importlib
import re
import uuid
from pathlib import Path

import jwt
import pytest
from django.apps import apps
from rest_framework import serializers as drf_serializers

from voicerooms.livekit import mint_join_token

# Identifier shapes that would mean content-key material had grown a server surface
# (§A9, §A12 content-key rows). `_?` keeps prose ("media key" in a comment) from
# tripping it while any identifier spelling (media_key, sframeKey, roomkey) does.
FORBIDDEN = re.compile(
    r"sframe|media_?key|room_?key|audio_?key|content_?key|session_?key|srtp|e2ee",
    re.IGNORECASE)

LOCAL_APPS = ["core", "accounts", "devices", "vault", "messaging", "attachments",
              "voicerooms", "realtime"]
BACKEND = Path(__file__).resolve().parent.parent.parent

# §A4 audits the framework tables once: Django's `session_key` is an opaque session
# identifier used only by the admin, not key material under the §A12 inventory. The
# same lone exemption core/tests/test_manifest.py grants — nothing else gets one.
AUDITED_FRAMEWORK_COLUMNS = {"sessions.Session.session_key"}


def test_the_pattern_itself_has_teeth_and_spares_infrastructure_names():
    # Vacuity guard: prove a real offender matches and §A12 infrastructure names do not.
    for offender in ("sframe_key", "mediaKey", "room_key", "srtp_master", "e2eeKey"):
        assert FORBIDDEN.search(offender), f"pattern missed {offender}"
    for legal in ("roomtoken", "LIVEKIT_API_SECRET", "JWT_SIGNING_KEY", "ik_pub",
                  "keypackage", "key_id", "name_blob"):
        assert not FORBIDDEN.search(legal), f"pattern false-positives on {legal}"


def test_no_model_field_anywhere_names_key_material():
    offenders = [f"{m._meta.label}.{f.name}"
                 for m in apps.get_models()
                 for f in m._meta.get_fields()
                 if FORBIDDEN.search(f.name)
                 and f"{m._meta.app_label}.{m.__name__}.{f.name}"
                 not in AUDITED_FRAMEWORK_COLUMNS]
    assert offenders == [], f"a media/content-key column exists: {offenders}"


def test_no_serializer_field_anywhere_names_key_material():
    offenders = []
    for app in LOCAL_APPS:
        try:
            module = importlib.import_module(f"{app}.serializers")
        except ModuleNotFoundError:
            continue
        for obj in vars(module).values():
            if isinstance(obj, type) and issubclass(obj, drf_serializers.BaseSerializer):
                for name in getattr(obj, "_declared_fields", {}):
                    if FORBIDDEN.search(name):
                        offenders.append(f"{app}.serializers.{obj.__name__}.{name}")
    assert offenders == [], f"a serializer accepts/returns key material: {offenders}"


def test_grep_of_the_schema_and_api_surface_finds_no_key_field():
    """The literal grep half (§A9 'grep-level test'): models, serializers, and the
    migrations that shape the schema."""
    offenders = []
    for app in LOCAL_APPS:
        for pattern in ("models.py", "serializers.py", "migrations/*.py"):
            for path in sorted((BACKEND / app).glob(pattern)):
                for lineno, line in enumerate(path.read_text().splitlines(), 1):
                    if FORBIDDEN.search(line):
                        offenders.append(f"{path.relative_to(BACKEND)}:{lineno}")
    assert offenders == [], f"key-material identifier in the schema/API surface: {offenders}"


def test_room_token_is_a_pure_video_grant_with_no_key_material(settings):
    secret = "an-infrastructure-secret-well-over-32-bytes-long"
    settings.LIVEKIT_API_KEY = "lk-key"
    settings.LIVEKIT_API_SECRET = secret
    settings.LIVEKIT_TOKEN_TTL_SECONDS = 300
    room_id, device_id = uuid.uuid4(), uuid.uuid4()

    token, _ttl = mint_join_token(room_id, device_id)
    claims = jwt.decode(token, secret, algorithms=["HS256"])

    # Exactly the LiveKit grant surface — nothing extra to smuggle a key inside.
    assert set(claims) == {"iss", "sub", "nbf", "iat", "exp", "video"}
    assert set(claims["video"]) == {"roomJoin", "room", "canPublish", "canSubscribe",
                                    "canPublishData", "canPublishSources"}
    assert claims["video"]["room"] == str(room_id)
    assert claims["sub"] == str(device_id)

    def walk(node, path):
        if isinstance(node, dict):
            for key, value in node.items():
                assert not FORBIDDEN.search(str(key)), f"key-material claim {path}.{key}"
                walk(value, f"{path}.{key}")
        elif isinstance(node, list):
            for i, value in enumerate(node):
                walk(value, f"{path}[{i}]")

    walk(claims, "token")

    # And the values carry no secret either: the only strings in the payload are the
    # issuer key id, the two UUIDs, and the microphone source tag.
    flat = [claims["iss"], claims["sub"], claims["video"]["room"],
            *claims["video"]["canPublishSources"]]
    assert secret not in flat
