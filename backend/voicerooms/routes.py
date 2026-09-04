"""The voice-room routes: create, read, rename, and mint a join token.

A room is a capability id and an encrypted name, and nothing else. Membership,
invites, roles and media keys are client state carried over pairwise sessions;
live participation exists only in Redis. Every route needs a full-scope token
bound to a live device, which is also what the LiveKit identity is cut from.
"""

import uuid

from django.conf import settings
from fastapi import APIRouter, Depends, Response, status

from api.auth import Principal, require_full_device
from api.errors import ApiError
from api.orm import run_unit
from api.ratelimit import rate_limit
from voicerooms import services
from voicerooms.livekit import mint_join_token
from voicerooms.presence import room_live_count
from voicerooms.schemas import RoomCreatedOut, RoomNameIn, RoomOut, RoomTokenOut

router = APIRouter(tags=["voicerooms"], dependencies=[Depends(require_full_device)])


@router.post(
    "/rooms",
    response_model=RoomCreatedOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def create_room(payload: RoomNameIn):
    """The returned id is the capability: anyone who learns it through an
    encrypted invite can read, rename, subscribe and join. There is no owner
    column and no member table."""
    return await run_unit(services.create, payload.raw)


@router.get(
    "/rooms/{room_id}",
    response_model=RoomOut,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def read_room(room_id: uuid.UUID):
    room = await run_unit(services.read, room_id)
    # Volatile, so it comes from Redis rather than a column. A Redis that is down
    # never reaches here: the limiter above shares the client and fails closed.
    return {**room, "live_count": await room_live_count(room_id)}


@router.put("/rooms/{room_id}", dependencies=[Depends(rate_limit("accounts"))])
async def rename_room(room_id: uuid.UUID, payload: RoomNameIn):
    await run_unit(services.rename, room_id, payload.raw)
    return Response(status_code=status.HTTP_200_OK)


@router.post(
    "/rooms/{room_id}/token",
    response_model=RoomTokenOut,
    dependencies=[Depends(rate_limit("roomtoken"))],
)
async def mint_room_token(
    room_id: uuid.UUID, principal: Principal = Depends(require_full_device)
):
    """Mint a LiveKit join token for this room and the calling device. The server
    signs the grant and never joins the media path."""
    await run_unit(services.require_room, room_id)
    if not (
        settings.LIVEKIT_URL and settings.LIVEKIT_API_KEY and settings.LIVEKIT_API_SECRET
    ):
        raise ApiError(503, "voice_unconfigured", "Voice is not configured.")
    token, ttl = mint_join_token(room_id, principal.device.id)
    return {"url": settings.LIVEKIT_URL, "token": token, "expires_in": ttl}
