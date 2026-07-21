import os

from django.conf import settings
from django.db.models import Sum
from django.http import HttpResponse
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsFullScope
from core.buckets import ATTACHMENT_BUCKETS

from .models import Attachment

BAD_REQUEST = {"code": "bad_request", "detail": "Expected a single `blob` file."}
BAD_BUCKET = {"code": "bad_bucket", "detail": "Invalid payload."}
QUOTA_EXCEEDED = {"code": "quota_exceeded", "detail": "Storage quota exhausted."}
NOT_FOUND = {"code": "not_found", "detail": "No such attachment."}


class UploadAttachmentView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "attachments"

    def post(self, request):
        f = request.FILES.get("blob")
        if f is None:
            return Response(BAD_REQUEST, status=400)
        size = f.size
        if size not in set(ATTACHMENT_BUCKETS):
            return Response(BAD_BUCKET, status=400)
        used = Attachment.objects.filter(uploader_id=request.user.id).aggregate(
            s=Sum("size"))["s"] or 0
        if used + size > settings.ATTACH_USER_QUOTA_BYTES:
            return Response(QUOTA_EXCEEDED, status=413)
        att = Attachment(uploader_id=request.user.id, size=size)
        path = att.disk_path()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as out:
            for chunk in f.chunks():
                out.write(chunk)
        att.save()
        return Response({"attachment_id": att.id, "size": size}, status=201)


class DownloadAttachmentView(APIView):
    """Any authenticated (active) user with a valid token may fetch by id — the capability id
    is the real gate (§A4). nginx streams the bytes via X-Accel-Redirect."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "attachments"

    def get(self, request, attachment_id):
        att = Attachment.objects.filter(id=attachment_id).only("id").first()
        if att is None:
            return Response(NOT_FOUND, status=404)
        resp = HttpResponse(status=200)
        resp["Content-Type"] = "application/octet-stream"
        # Opaque ciphertext is never something a browser should render or a cache should
        # keep: fixed type, forced download, no shared caching of a private object.
        resp["Content-Disposition"] = "attachment"
        resp["Cache-Control"] = "private, no-store"
        # att.id is server-generated base64url read back from the DB, so the path cannot
        # be steered by the caller and carries no traversal or header-injection payload.
        resp["X-Accel-Redirect"] = f"/_protected_attachments/{att.id[:2]}/{att.id}"
        return resp
