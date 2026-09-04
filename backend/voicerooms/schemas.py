"""The inbound and outbound models of the voice-room surface.

The one request model forbids an unknown field and runs in strict mode, like
every other inbound model of this API.
"""

import datetime
import uuid
from typing import Annotated

from pydantic import BaseModel, Field, PrivateAttr, model_validator

from accounts.schemas import RequestModel
from core.buckets import NAME_BUCKETS
from core.fields import decode_blob_or_400

# Base64 of the largest bucket plus padding headroom: bounds what reaches
# b64decode; the exact length check is decode_blob_or_400's job.
MAX_NAME_CHARS = 4 * ((max(NAME_BUCKETS) + 2) // 3) + 8


class RoomNameIn(RequestModel):
    name_blob: Annotated[str, Field(min_length=1, max_length=MAX_NAME_CHARS)]

    _raw: bytes = PrivateAttr(default=b"")

    @property
    def raw(self):
        return self._raw

    @model_validator(mode="after")
    def _decode(self):
        # After the fields, not before: `BadBucket` carries its own code and never
        # echoes the payload, so a body that is missing the field entirely must
        # answer `invalid_request` first.
        self._raw = decode_blob_or_400(self.name_blob, NAME_BUCKETS)
        return self


class RoomCreatedOut(BaseModel):
    room_id: uuid.UUID


class RoomOut(BaseModel):
    room_id: uuid.UUID
    name_blob: str
    updated_date: datetime.date
    live_count: int


class RoomTokenOut(BaseModel):
    url: str
    token: str
    expires_in: int
