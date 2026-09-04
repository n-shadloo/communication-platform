"""The vault route: one key backup for each account, opaque to this server."""

from fastapi import APIRouter, Depends, Response, status

from api.auth import Principal, require_full_device
from api.orm import run_unit
from api.ratelimit import rate_limit
from api.schema import FULL_DEVICE, errors
from vault import services
from vault.schemas import KeyBackupIn, KeyBackupOut

router = APIRouter(tags=["vault"], dependencies=[Depends(require_full_device)])


@router.get(
    "/me/keybackup",
    response_model=KeyBackupOut,
    responses=errors(*FULL_DEVICE, "not_found", "throttled"),
    dependencies=[Depends(rate_limit("accounts"))],
)
async def read_key_backup(principal: Principal = Depends(require_full_device)):
    return await run_unit(services.read, principal.user.id)


@router.put(
    "/me/keybackup",
    # An empty body, so the document declares the status and no content rather
    # than the untyped object FastAPI would publish for a route with no model.
    response_class=Response,
    responses=errors(
        *FULL_DEVICE,
        "invalid_request",
        "bad_bucket",
        "stale_version",
        "payload_too_large",
        "throttled",
    ),
    dependencies=[Depends(rate_limit("accounts"))],
)
async def write_key_backup(
    payload: KeyBackupIn, principal: Principal = Depends(require_full_device)
):
    await run_unit(services.write, principal.user.id, payload.raw, payload.version)
    return Response(status_code=status.HTTP_200_OK)
