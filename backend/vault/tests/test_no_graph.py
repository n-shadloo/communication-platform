"""No-graph proof for vault_keybackup, the vault's only remaining table.

A dump of the table shows only {user_id, blob, version, updated_date}: the blob is
an exact bucket length, updated_date is day-coarse, and the single user reference
is the backup's owner. No column links a second user, and no history table exists
in this app at all (vault/tests/test_no_history.py proves that removal).
"""

import datetime

import pytest
from django.db import connection

from core.buckets import BACKUP_BUCKETS
from vault.models import KeyBackup

from .conftest import KEYBACKUP_URL, backup_blob

pytestmark = pytest.mark.django_db

EXPECTED_COLUMNS = {"user_id", "blob", "version", "updated_date"}


def test_keybackup_columns_are_exactly_the_minimum():
    with connection.cursor() as cur:
        columns = {
            c.name
            for c in connection.introspection.get_table_description(
                cur, KeyBackup._meta.db_table
            )
        }
    assert columns == EXPECTED_COLUMNS, columns

    # The only foreign key to a user is the owner; there is no second-user column.
    user_fks = [
        f.name
        for f in KeyBackup._meta.get_fields()
        if getattr(f, "many_to_one", False) or getattr(f, "one_to_one", False)
    ]
    assert user_fks == ["user"]


def test_stored_blob_is_bucket_sized_and_date_is_day_coarse(
    api, active_user, device, auth_headers
):
    api.put(
        KEYBACKUP_URL,
        {"blob": backup_blob(), "version": 1},
        format="json",
        **auth_headers(active_user, device),
    )
    backup = KeyBackup.objects.get(user_id=active_user.id)

    assert len(bytes(backup.blob)) in set(BACKUP_BUCKETS)
    # A pure date, never a timestamp (datetime is a subclass of date, so exclude it).
    assert isinstance(backup.updated_date, datetime.date)
    assert not isinstance(backup.updated_date, datetime.datetime)
