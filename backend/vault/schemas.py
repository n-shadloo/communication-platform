from typing import Annotated

from pydantic import BaseModel, Field, model_validator

from accounts.schemas import BlobIn
from core.buckets import BACKUP_BUCKETS
from core.fields import decode_blob_or_400

# Base64 of the largest bucket plus padding headroom: bounds what reaches
# b64decode; the exact length check is decode_blob_or_400's job.
MAX_BACKUP_CHARS = 4 * ((max(BACKUP_BUCKETS) + 2) // 3) + 8


class KeyBackupIn(BlobIn):
    blob: Annotated[str, Field(max_length=MAX_BACKUP_CHARS)]

    @model_validator(mode="after")
    def _decode(self):
        self._raw = decode_blob_or_400(self.blob, BACKUP_BUCKETS)
        return self


class KeyBackupOut(BaseModel):
    blob: str
    version: int
