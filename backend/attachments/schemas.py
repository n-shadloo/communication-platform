"""The outbound model of the attachment surface.

There is no inbound model: the upload carries a multipart body rather than JSON,
and `attachments/routes.py` parses it under limits Pydantic has no say over.
"""

from pydantic import BaseModel


class AttachmentOut(BaseModel):
    attachment_id: str
    size: int
