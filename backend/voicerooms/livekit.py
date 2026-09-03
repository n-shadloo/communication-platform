import time

import jwt  # PyJWT; no LiveKit SDK, no foreign dependency
from django.conf import settings


def mint_join_token(room_id, device_id):
    """A short-lived LiveKit access token: a JWT signed with the LiveKit API secret
    (an infrastructure secret, not a media key). Grants audio join/publish/subscribe
    for exactly this room and this device. No media key is included; each sender's
    media key is generated client-side, distributed over pairwise sessions, and never
    reaches the server or the SFU."""
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
            # The grant covers audio only: microphone is the single publishable
            # source, and the LiveKit data channel stays closed. Ephemeral room text
            # rides the WS `room.<id>` group, never the SFU.
            "canPublishData": False,
            "canPublishSources": ["microphone"],
        },
    }
    token = jwt.encode(payload, settings.LIVEKIT_API_SECRET, algorithm="HS256")
    return token, ttl
