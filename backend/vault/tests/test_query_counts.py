"""Query-shape guards for the key-backup route.

Counted end to end through the composed application, so each number includes the
one query the authentication dependency makes. Transaction statements are
excluded, so the number is the database work itself.
"""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from .conftest import KEYBACKUP_URL, backup_blob

pytestmark = pytest.mark.django_db(transaction=True)

TRANSACTION_STATEMENTS = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE", "ROLLBACK")

AUTH_QUERY = 1  # the device row, joined to its owner


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


def test_reading_the_backup_is_one_lookup(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    http.put(KEYBACKUP_URL, json={"blob": backup_blob(), "version": 1}, headers=headers)

    response = counted(http, "GET", KEYBACKUP_URL, AUTH_QUERY + 1, headers=headers)

    assert response.status_code == 200


def test_a_write_is_the_owner_lock_the_version_probe_and_one_upsert(
    http, active_user, device, bearer
):
    """The owner row is locked because the backup row may not exist yet; the
    version probe reads the stored version without dragging the blob back with it;
    update_or_create is the remaining SELECT and write."""
    headers = bearer(active_user, device)

    response = counted(
        http,
        "PUT",
        KEYBACKUP_URL,
        AUTH_QUERY + 4,
        json={"blob": backup_blob(), "version": 1},
        headers=headers,
    )

    assert response.status_code == 200
