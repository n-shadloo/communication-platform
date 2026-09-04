"""The messaging routes: send a batch, drain a mailbox, ack what arrived.

Every route needs a full-scope token bound to a live device. The device is the
mailbox, so a token that names none has nothing to reach here.
"""

from fastapi import APIRouter, Depends, status

from api.auth import Principal, require_full_device
from api.orm import run_unit
from api.ratelimit import rate_limit
from api.schema import FULL_DEVICE, errors
from messaging import services
from messaging.schemas import AckIn, AckOut, DrainOut, SendIn, SendOut, clamp_limit

router = APIRouter(tags=["messaging"], dependencies=[Depends(require_full_device)])


@router.post(
    "/envelopes",
    response_model=SendOut,
    status_code=status.HTTP_202_ACCEPTED,
    responses=errors(
        *FULL_DEVICE,
        "invalid_request",
        "bad_bucket",
        "payload_too_large",
        "throttled",
    ),
    dependencies=[Depends(rate_limit("envelopes"))],
)
async def send_envelopes(payload: SendIn):
    """The sender is used only for throttling and is never written; each recipient
    device gets its own copy."""
    accepted, stale, full = await run_unit(services.send, payload.messages)
    # After the unit, never inside it: a push from an open transaction would
    # announce rows a reader cannot see yet, and a channel layer that is down must
    # not fail a send whose rows are already committed.
    await services.push(accepted)
    return {"accepted": len(accepted), "stale_devices": stale, "full_devices": full}


@router.get(
    "/me/envelopes",
    response_model=DrainOut,
    responses=errors(*FULL_DEVICE, "throttled"),
    dependencies=[Depends(rate_limit("envelopes"))],
)
async def drain_envelopes(
    limit: str | None = None, principal: Principal = Depends(require_full_device)
):
    envelopes, has_more = await run_unit(
        services.drain, principal.device.id, clamp_limit(limit)
    )
    return {
        "envelopes": envelopes,
        "has_more": has_more,
        # A client whose last acked seq is below this lost envelopes to the TTL
        # prune — possibly ratchet messages or control events — and must repair the
        # affected pairwise sessions (CLIENT_CONTRACT.md §H). It rides on the
        # device the token already loaded, so the drain costs one query.
        "pruned_through": principal.device.queue_pruned_through,
    }


@router.post(
    "/me/envelopes/ack",
    response_model=AckOut,
    responses=errors(*FULL_DEVICE, "invalid_request", "payload_too_large", "throttled"),
    dependencies=[Depends(rate_limit("envelopes"))],
)
async def ack_envelopes(
    payload: AckIn, principal: Principal = Depends(require_full_device)
):
    return await run_unit(services.ack, principal.device.id, payload.ids)
