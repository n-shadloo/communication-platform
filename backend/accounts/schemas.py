"""The inbound and outbound models of the accounts surface.

Every request model forbids an unknown field, so a typo or an injected key is a
refusal rather than a silently dropped value, and every one of them runs in
strict mode, so a value the annotation does not name is refused rather than
converted. Every string and integer carries the bound its serializer carried.
"""

import uuid
from typing import Annotated, Literal

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    PrivateAttr,
    field_validator,
    model_validator,
)
from pydantic_core import PydanticCustomError

from accounts.models import username_validator
from core.buckets import PROFILE_BUCKETS
from core.fields import decode_blob_or_400

# Base64 of the largest profile bucket plus headroom; the exact length check is
# decode_blob_or_400's job.
MAX_PROFILE_CHARS = 8192


class RequestModel(BaseModel):
    """Every inbound model of every app derives from this one."""

    model_config = ConfigDict(extra="forbid", strict=True)


class BlobIn(RequestModel):
    """A `{blob, version}` body whose blob decodes to an exact bucket length.

    The decode runs in an after-validator, so it runs only once every field has
    validated and a missing `version` stays an `invalid_request` instead of
    becoming a `bad_bucket`. `BadBucket` is deliberately not a validation error:
    it carries its own code and never echoes the payload.
    """

    version: Annotated[int, Field(ge=0)]
    _raw: bytes = PrivateAttr(default=b"")

    @property
    def raw(self):
        return self._raw


class RegisterIn(RequestModel):
    username: Annotated[str, Field(max_length=32)]
    password: Annotated[str, Field(max_length=256)]

    @field_validator("username")
    @classmethod
    def _normalise(cls, value):
        # The `^[a-z0-9_]{3,32}$` rule is applied after lowercasing, because the
        # User manager and the model both normalise, so "BoB" is "bob".
        value = value.lower()
        try:
            username_validator(value)
        except DjangoValidationError as exc:
            # PydanticCustomError rather than ValueError: pydantic prefixes a
            # ValueError's message with "Value error, ", and the client shows the
            # message rather than the exception class that carried it.
            raise PydanticCustomError("username_shape", " ".join(exc.messages))
        return value

    @field_validator("password")
    @classmethod
    def _strong_enough(cls, value):
        try:
            validate_password(value)
        except DjangoValidationError as exc:
            raise PydanticCustomError("password_strength", " ".join(exc.messages))
        return value


class LoginIn(RequestModel):
    """Login parses anonymous input, so every field is typed here: a non-string
    username and a non-UUID device id are both unauthenticated `500`s otherwise.
    The username shape is deliberately not validated — a badly shaped name is
    wrong credentials, not a malformed request."""

    username: Annotated[str, Field(max_length=32)]
    password: Annotated[str, Field(max_length=256)]
    # strict=False on this one field: FastAPI validates a decoded body as Python
    # objects, and strict mode there admits only a UUID instance, which JSON
    # cannot carry. Lax UUID accepts a string and bytes and nothing else, so no
    # value changes shape on the way in.
    device_id: Annotated[uuid.UUID | None, Field(strict=False)] = None


class RefreshIn(RequestModel):
    refresh: Annotated[str, Field(max_length=4096)]


class ProfileIn(BlobIn):
    blob: Annotated[str, Field(max_length=MAX_PROFILE_CHARS)]

    @model_validator(mode="after")
    def _decode(self):
        self._raw = decode_blob_or_400(self.blob, PROFILE_BUCKETS)
        return self


class RegisterOut(BaseModel):
    user_id: str


class TokenPairOut(BaseModel):
    access: str
    refresh: str


class RegisterScopeOut(BaseModel):
    """The login answer when the request named no live device of the account: a
    short token whose only power is `POST /me/devices`. It carries no refresh
    token, because the pair a refresh rotates is bound to a device."""

    scope: Literal["register"]
    access: str
    user_id: str


class FullScopeOut(BaseModel):
    """The login answer when the request named a live device of the account."""

    scope: Literal["full"]
    access: str
    refresh: str
    user_id: str
    device_id: str


# Discriminated on `scope`, which is the field the client reads to tell the two
# apart, so the document carries the same branch the handler does rather than a
# free-form object a client has to probe.
LoginOut = Annotated[RegisterScopeOut | FullScopeOut, Field(discriminator="scope")]


class DirectoryUserOut(BaseModel):
    user_id: str
    username: str


class DirectoryOut(BaseModel):
    users: list[DirectoryUserOut]


class ProfileOut(BaseModel):
    blob: str
    version: int
