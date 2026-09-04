"""The inbound and outbound models of the messaging surface, and its limits.

Every request model forbids an unknown field and runs in strict mode. The one
relaxation is `strict=False` on each UUID: FastAPI validates a decoded body as
Python objects, and strict mode there admits only a `uuid.UUID` instance, which
JSON cannot carry. Lax UUID accepts a string and bytes and nothing else, so no
value changes shape on the way in.
"""

import uuid
from typing import Annotated

from pydantic import BaseModel, Field, PrivateAttr, model_validator

from accounts.schemas import RequestModel
from core.buckets import ENVELOPE_BUCKETS
from core.fields import decode_blob_or_400

# Base64 length cap for the largest bucket plus padding headroom; the exact size check
# is decode_blob_or_400's job. Without the cap a client could push an arbitrarily long
# string into b64decode. Computed because ENVELOPE_BUCKETS is settings-tunable.
MAX_BLOB_CHARS = 4 * ((max(ENVELOPE_BUCKETS) + 2) // 3) + 8

MAX_SEND_BATCH = 256
MAX_DRAIN_LIMIT = 100
MAX_ACK_IDS = 200

# The relaxation goes on the identifier itself, never on the list around it: a
# `strict=False` on the list is read as the list's own strictness and leaves the
# items strict.
LaxUuid = Annotated[uuid.UUID, Field(strict=False)]


def clamp_limit(limit):
    """The page size, which never errors: a non-numeric value falls back to the cap
    and a negative one clamps to 1, which is the contract `messaging/API.md`
    publishes. Declared as an integer instead, a stale client would answer 400 on
    the one route it polls."""
    try:
        requested = int(limit)
    except (TypeError, ValueError):
        return MAX_DRAIN_LIMIT
    return max(1, min(requested, MAX_DRAIN_LIMIT))


class OutgoingItemIn(RequestModel):
    device_id: LaxUuid
    blob: Annotated[str, Field(min_length=1, max_length=MAX_BLOB_CHARS)]

    _raw: bytes = PrivateAttr(default=b"")

    @property
    def raw(self):
        return self._raw

    @model_validator(mode="after")
    def _decode(self):
        # After the fields, not before: `BadBucket` carries its own code and never
        # echoes the payload, so a body that is also missing `device_id` must answer
        # `invalid_request` first.
        self._raw = decode_blob_or_400(self.blob, ENVELOPE_BUCKETS)
        return self


class SendIn(RequestModel):
    messages: Annotated[
        list[OutgoingItemIn], Field(min_length=1, max_length=MAX_SEND_BATCH)
    ]


class AckIn(RequestModel):
    ids: Annotated[list[LaxUuid], Field(max_length=MAX_ACK_IDS)] = []


class SendOut(BaseModel):
    accepted: int
    stale_devices: list[str]
    full_devices: list[str]


class EnvelopeOut(BaseModel):
    id: str
    seq: int
    blob: str


class DrainOut(BaseModel):
    envelopes: list[EnvelopeOut]
    has_more: bool
    pruned_through: int


class AckOut(BaseModel):
    deleted: int
