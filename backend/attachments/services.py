"""The synchronous units of work behind the attachment routes."""

import os

from django.conf import settings
from django.db import transaction
from django.db.models import Sum

from accounts.models import User
from api.errors import ApiError
from attachments.models import Attachment

NOT_FOUND = "No such attachment."


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

    A NUL byte is the third: PostgreSQL text carries none, so psycopg refuses the
    statement rather than returning no row, and the route raised instead of
    answering without this (AR-10). A capability id is base64url of 32 random
    bytes, so no stored id can hold one — an id carrying it is an id nobody has,
    which is the answer below. This is a malformed-input guard, never a control:
    the unguessable id is the whole access check.
    """
    if "\x00" in attachment_id:
        raise ApiError(404, "not_found", NOT_FOUND)
    stored = Attachment.objects.filter(id=attachment_id).only("id").first()
    if stored is None:
        raise ApiError(404, "not_found", NOT_FOUND)
    return stored.id


def purge(attachments, audit=None):
    """Delete these attachment rows and unlink their bytes.

    The one write path that removes an attachment. `manage.py prune` calls it for
    the retention sweep and the admin panel calls it for the operator's own
    deletion, so the order below is the order both get.

    Unlink before deleting the row: a crash in between leaves a row whose bytes are
    already gone, which the next pass clears. Dropping the row first would strand
    the file, since cleanup only ever walks rows.

    `audit` is called once, with the rows that are about to go, before the delete.
    The retention sweep passes none — a scheduled expiry is not an administrative
    act and no operator performed it.
    """
    doomed = []
    removed_files = 0
    for attachment in attachments:
        try:
            os.remove(attachment.disk_path())
            removed_files += 1
        except FileNotFoundError:
            pass  # already gone; the row still needs clearing
        except OSError:
            # One unreadable file must not stop the sweep. The rows go in a single
            # pass below, so an escaping error would stall retention entirely.
            continue
        doomed.append(attachment)
    if audit is not None and doomed:
        audit(doomed)
    deleted, _ = Attachment.objects.filter(
        id__in=[attachment.id for attachment in doomed]
    ).delete()
    return deleted, removed_files
