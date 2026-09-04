"""Query-shape guard for the attachment routes.

Counted end to end through the composed application, so each number includes the
one query the authentication dependency makes: the device row joined to its
owner. `transaction=True` makes the transaction statements real BEGIN/COMMIT
rather than savepoints, and they are excluded here so the number is the database
work itself.
"""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS

pytestmark = pytest.mark.django_db(transaction=True)

TRANSACTION_STATEMENTS = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE", "ROLLBACK")

AUTH_QUERY = 1  # the device row, joined to its owner
# The uploader's row lock, one SUM aggregate, one insert. Fixed: none of the three
# scales with how many attachments the account already holds.
UPLOAD_QUERIES = 3

UPLOAD_URL = "/api/v1/attachments"
SMALLEST = min(ATTACHMENT_BUCKETS)


def counted(http, method, url, expected, **kwargs):
    with CaptureQueriesContext(connection) as context:
        response = http.request(method, url, **kwargs)
    sqls = [
        query["sql"]
        for query in context.captured_queries
        if not query["sql"].startswith(TRANSACTION_STATEMENTS)
    ]
    assert len(sqls) == expected, "\n".join(sqls)
    return response


@pytest.mark.parametrize("existing", [0, 25])
def test_the_quota_check_is_one_aggregate_however_many_files_exist(
    http, active_user, device, bearer, existing
):
    """The quota must stay a single SUM pushed to the database, never a fetch-and-add
    over the user's rows."""
    Attachment.objects.bulk_create(
        [Attachment(uploader=active_user, size=SMALLEST) for _ in range(existing)]
    )

    resp = counted(
        http,
        "POST",
        UPLOAD_URL,
        AUTH_QUERY + UPLOAD_QUERIES,
        files={"blob": ("blob", b"\x01" * SMALLEST)},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 201


def test_the_download_is_a_single_lookup(http, active_user, device, bearer):
    cap = http.post(
        UPLOAD_URL,
        files={"blob": ("blob", b"\x01" * SMALLEST)},
        headers=bearer(active_user, device),
    ).json()["attachment_id"]

    resp = counted(
        http,
        "GET",
        f"{UPLOAD_URL}/{cap}",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 200
