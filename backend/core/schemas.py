from pydantic import BaseModel


class HealthOut(BaseModel):
    """Liveness and nothing else: no version, no build, no component status."""

    status: str
