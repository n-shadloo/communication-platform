"""The synchronous units of work behind the attachment routes."""

from django.conf import settings
from django.db import transaction
from django.db.models import Sum

from accounts.models import User
from api.errors import ApiError
from attachments.models import Attachment


def record(attachment):
    """Charge the upload against the quota and insert its row, in one transaction.

    The check and the insert are one unit under the uploader's row lock, because
    apart they are a race: two in-flight uploads both read the same SUM, both
    pass, and the account ends above its quota. Only the same account blocks here.

    The bytes are already on disk when this runs, so a refusal leaves a file that
    no row names and the caller drops it. The other order — insert, then write —
    would leave a row a download could reach with nothing behind it.
    """
    with transaction.atomic():
        User.objects.select_for_update().filter(pk=attachment.uploader_id).only(
            "id"
        ).first()
        used = (
            Attachment.objects.filter(uploader_id=attachment.uploader_id).aggregate(
                s=Sum("size")
            )["s"]
            or 0
        )
        if used + attachment.size > settings.ATTACH_USER_QUOTA_BYTES:
            raise ApiError(413, "quota_exceeded", "Storage quota exhausted.")
        attachment.save()


def locate(attachment_id):
    """The capability id, read back from the row that holds it.

    Only the id: the row carries the uploader, and the response must name nobody.
    A missing row and a pruned one are the same answer.
    """
    stored = Attachment.objects.filter(id=attachment_id).only("id").first()
    if stored is None:
        raise ApiError(404, "not_found", "No such attachment.")
    return stored.id
