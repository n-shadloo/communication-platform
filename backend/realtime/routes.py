"""The relay route: the whole HTTP surface of voice.

One route, and it is the only one of this API with no unit of work behind it: it
reads no row and writes none, because a coturn credential is computed from a
shared secret rather than stored (`realtime/relay.py`). The socket half of this
app is `realtime/gateway.py`, which declares no dependency here because it
authenticates the handshake itself.
"""

from django.conf import settings
from fastapi import APIRouter, Depends

from api.auth import require_full_device
from api.errors import ApiError
from api.ratelimit import rate_limit
from api.schema import FULL_DEVICE, errors
from realtime import relay
from realtime.schemas import RelayCredentialOut

router = APIRouter(tags=["realtime"], dependencies=[Depends(require_full_device)])

UNCONFIGURED = "This deployment serves no voice relay."


@router.post(
    "/me/relay",
    response_model=RelayCredentialOut,
    responses=errors(*FULL_DEVICE, "voice_unconfigured", "throttled"),
    dependencies=[Depends(rate_limit("relay"))],
)
async def mint_relay_credential():
    """Mint an ephemeral coturn credential for the calling device.

    Safe to repeat: every call mints a fresh username, and a credential already
    issued stays good until its own expiry, so a client that retries a timed-out
    request holds two working credentials rather than none.

    An unconfigured deployment answers `503 voice_unconfigured` rather than a
    credential no relay would accept. It is not a backoff: `TURN_URLS` is empty,
    so this server does not do voice, and a retry will not make a relay appear.
    The route reads the setting and never reaches coturn, so a relay that is
    configured but down is a `200` and a call that fails to connect.
    """
    if not settings.TURN_URLS:
        raise ApiError(503, "voice_unconfigured", UNCONFIGURED)
    return relay.mint()
