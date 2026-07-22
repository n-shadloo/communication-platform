import time

import jwt  # PyJWT (pinned in Prompt 1); no LiveKit SDK / no foreign dependency
from django.conf import settings


def mint_join_token(room_id, device_id):
    """A short-lived LiveKit access token: a JWT signed with the LiveKit API secret (an
    infrastructure secret, NOT a media key — §A12). Grants audio join/publish/subscribe for
    exactly this room + this device. No media key is included; SFrame keys are derived
    client-side from the live MLS subgroup and never reach the server or SFU (§A9)."""
    now = int(time.time())
    ttl = settings.LIVEKIT_TOKEN_TTL_SECONDS
    payload = {
        "iss": settings.LIVEKIT_API_KEY,
        "sub": str(device_id),
        "nbf": now,
        "iat": now,
        "exp": now + ttl,
        "video": {
            "roomJoin": True,
            "room": str(room_id),
            "canPublish": True,
            "canSubscribe": True,
            # §A9 scopes the grant to publish+subscribe *audio only*: microphone is the
            # single publishable source, and the LiveKit data channel stays closed —
            # ephemeral room text rides the WS `room.<id>` group (§A6), never the SFU.
            "canPublishData": False,
            "canPublishSources": ["microphone"],
        },
    }
    token = jwt.encode(payload, settings.LIVEKIT_API_SECRET, algorithm="HS256")
    return token, ttl
