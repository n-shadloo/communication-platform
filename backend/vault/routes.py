"""The vault route: one key backup for each account, opaque to this server."""

from fastapi import APIRouter, Depends, Response, status

from api.auth import Principal, require_full_device
from api.orm import run_unit
from api.ratelimit import rate_limit
from vault import services
from vault.schemas import KeyBackupIn, KeyBackupOut

router = APIRouter(tags=["vault"], dependencies=[Depends(require_full_device)])


@router.get(
    "/me/keybackup",
    response_model=KeyBackupOut,
    dependencies=[Depends(rate_limit("accounts"))],
)
async def read_key_backup(principal: Principal = Depends(require_full_device)):
    return await run_unit(services.read, principal.user.id)


@router.put("/me/keybackup", dependencies=[Depends(rate_limit("accounts"))])
async def write_key_backup(
    payload: KeyBackupIn, principal: Principal = Depends(require_full_device)
):
    await run_unit(services.write, principal.user.id, payload.raw, payload.version)
    return Response(status_code=status.HTTP_200_OK)
