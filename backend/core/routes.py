from fastapi import APIRouter, Depends

from api.auth import allow_anonymous
from api.schema import errors
from core.schemas import HealthOut

router = APIRouter(tags=["core"])


@router.get(
    "/health",
    response_model=HealthOut,
    responses=errors(),
    dependencies=[Depends(allow_anonymous)],
)
async def health():
    """The client's startup reachability probe. It reads no state, so it needs no
    unit of work and carries no throttle scope."""
    return {"status": "ok"}
