"""The attachment routes: opaque bytes in, a capability id out.

Both routes need a full-scope token bound to a live device. Beyond that the
unguessable id is the whole access control: the server keeps no recipient list
and no ACL, because one would rebuild the conversation graph the schema avoids.
"""

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import APIRouter, Depends, Request, Response, status
from starlette.concurrency import run_in_threadpool
from starlette.datastructures import UploadFile
from starlette.formparsers import MultiPartException, MultiPartParser
from starlette.requests import ClientDisconnect

from api.auth import Principal, require_full_device
from api.errors import ApiError
from api.orm import run_unit
from api.ratelimit import rate_limit
from api.schema import FULL_DEVICE, errors
from attachments import services
from attachments.models import Attachment
from attachments.schemas import AttachmentOut
from core.buckets import ATTACHMENT_BUCKETS
from core.fields import BadBucket

router = APIRouter(tags=["attachments"], dependencies=[Depends(require_full_device)])

FIELD = "blob"
MULTIPART = "multipart/form-data"
# The bytes never cross the process in one piece: one chunk is held while it moves
# from the spool to the bucketed file, whatever the size of the attachment.
CHUNK_BYTES = 64 * 1024
BUCKET_SIZES = frozenset(ATTACHMENT_BUCKETS)
# Never a description of what arrived: an error body of this surface echoes no
# request input, and the shape of a malformed body is input.
MALFORMED = {FIELD: ["Expected one multipart file part named `blob`."]}


class _SingleFileParser(MultiPartParser):
    """Starlette's multipart parser with a spool that holds no attachment.

    `spool_max_size` is the size above which a file part rolls from memory to a
    temporary file. Starlette's default is 1 MiB, which is three of the six
    attachment buckets held whole in the memory of a 1 GB host. Dropped to the
    copy chunk, the parse costs one chunk however large the body is. It is a
    documented class attribute, and `Request.form()` takes no argument for it.
    """

    spool_max_size = CHUNK_BYTES


@asynccontextmanager
async def _blob_part(request):
    """The one `blob` file part of the request, under explicit multipart limits.

    Parsed here rather than declared as an `UploadFile` parameter, because FastAPI
    exposes none of the three limits and the middleware that would set them parses
    the body a second time — which spools a 64 MiB attachment twice. `max_files=1`
    with `max_fields=0` is the whole contract: one file part named `blob`, and
    nothing else. Without them Starlette admits a thousand parts, each with a
    spool file of its own.
    """
    if not request.headers.get("content-type", "").startswith(MULTIPART):
        raise ApiError(400, "invalid_request", MALFORMED)
    parser = _SingleFileParser(
        request.headers, request.stream(), max_files=1, max_fields=0
    )
    try:
        form = await parser.parse()
    except MultiPartException:
        raise ApiError(400, "invalid_request", MALFORMED)
    except ClientDisconnect:
        # `api.middleware.BodyCap` refuses an oversized body by answering the
        # read with a disconnect, so this is the path a body above the route cap
        # takes. The refusal has to be a response rather than an escaping
        # exception: the cap drops whatever the route answers and sends its own
        # `413` in its place, and an exception would carry neither.
        raise ApiError(400, "invalid_request", MALFORMED)
    try:
        part = form.get(FIELD)
        if not isinstance(part, UploadFile):
            raise ApiError(400, "invalid_request", MALFORMED)
        yield part
    finally:
        await form.close()


def _spool_to_disk(source, path):
    """Copy the uploaded part to `path`, one bounded chunk at a time."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as out:
        while chunk := source.read(CHUNK_BYTES):
            out.write(chunk)


def _discard(path):
    Path(path).unlink(missing_ok=True)


# Declared rather than introspected: the route parses the multipart body itself,
# under limits FastAPI exposes no parameter for, so it declares no `UploadFile`
# and the generator sees no body at all. This is the one non-JSON body of the
# API, and a document that omitted it would send a client hunting.
MULTIPART_BODY = {
    "requestBody": {
        "required": True,
        "content": {
            MULTIPART: {
                "schema": {
                    "type": "object",
                    "required": [FIELD],
                    "properties": {
                        FIELD: {
                            "type": "string",
                            "format": "binary",
                            "description": (
                                "One already-encrypted, already-padded blob, of "
                                "exactly one attachment bucket length."
                            ),
                        }
                    },
                }
            }
        },
    }
}


@router.post(
    "/attachments",
    response_model=AttachmentOut,
    status_code=status.HTTP_201_CREATED,
    openapi_extra=MULTIPART_BODY,
    responses=errors(
        *FULL_DEVICE,
        "invalid_request",
        "bad_bucket",
        "payload_too_large",
        "quota_exceeded",
        "throttled",
    ),
    dependencies=[Depends(rate_limit("attachments"))],
)
async def upload_attachment(
    request: Request, principal: Principal = Depends(require_full_device)
):
    """Store one already-encrypted, already-padded blob under a fresh capability id.

    The bytes reach the disk before any row names them, which is the order that
    keeps a failed write off the download path: no row exists for a file that was
    never finished. The reverse order would publish a capability id for bytes that
    are not there.
    """
    async with _blob_part(request) as part:
        if part.size not in BUCKET_SIZES:
            raise BadBucket()
        attachment = Attachment(uploader_id=principal.user.id, size=part.size)
        path = attachment.disk_path()
        # Off the event loop: the copy is blocking file I/O, and 64 MiB of it on
        # the loop stalls every other request in the process.
        await run_in_threadpool(_spool_to_disk, part.file, path)
    try:
        await run_unit(services.record, attachment)
    except BaseException:
        # A quota refusal, or anything else, leaves bytes that no row names and
        # nothing can reach. Drop them rather than let a refused upload consume
        # the disk the quota exists to protect.
        await run_in_threadpool(_discard, path)
        raise
    return {"attachment_id": attachment.id, "size": attachment.size}


@router.get(
    "/attachments/{attachment_id}",
    # nginx replaces the body, so this process declares the bytes the client
    # receives rather than the empty response it returns itself.
    response_class=Response,
    responses={
        status.HTTP_200_OK: {
            "description": "The stored blob.",
            "content": {
                "application/octet-stream": {
                    "schema": {"type": "string", "format": "binary"}
                }
            },
        },
        **errors(*FULL_DEVICE, "not_found", "throttled"),
    },
    dependencies=[Depends(rate_limit("attachments"))],
)
async def download_attachment(attachment_id: str):
    """Hand the bytes to nginx. This process never streams a file.

    Any live token may fetch by id; the unguessable id is the gate. The path is
    built from the id the row holds, which is server-generated, so no request
    value ever steers it.
    """
    stored = await run_unit(services.locate, attachment_id)
    return Response(
        status_code=status.HTTP_200_OK,
        media_type="application/octet-stream",
        headers={
            # Opaque ciphertext is never something a browser should render or a
            # cache should keep: forced download, no shared caching.
            "Content-Disposition": "attachment",
            "Cache-Control": "private, no-store",
            "X-Accel-Redirect": f"/_protected_attachments/{stored[:2]}/{stored}",
        },
    )
