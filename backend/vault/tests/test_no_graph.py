"""No-graph proof for vault_historyrecord.

A dump of the table shows only {id, owner_id, seq, blob, stored_date}: the blob is an
exact bucket length, stored_date is day-coarse, and the single user reference is
`owner`, the log owner. No column links a second user.
"""
import datetime

import pytest
from django.db import connection

from core.buckets import ENVELOPE_BUCKETS
from vault.models import HistoryRecord
from .conftest import HISTORY_URL, history_blob

pytestmark = pytest.mark.django_db

EXPECTED_COLUMNS = {"id", "owner_id", "seq", "blob", "stored_date"}


def test_historyrecord_columns_are_exactly_the_minimum():
    with connection.cursor() as cur:
        columns = {c.name for c in connection.introspection.get_table_description(
            cur, HistoryRecord._meta.db_table)}
    assert columns == EXPECTED_COLUMNS, columns

    # The only foreign key to a user is `owner`; there is no second-user column.
    user_fks = [f.name for f in HistoryRecord._meta.get_fields()
                if getattr(f, "many_to_one", False)]
    assert user_fks == ["owner"]


def test_stored_blob_is_bucket_sized_and_date_is_day_coarse(api, active_user, device,
                                                            auth_headers):
    api.post(HISTORY_URL, {"records": [{"blob": history_blob()}]},
             format="json", **auth_headers(active_user, device))
    rec = HistoryRecord.objects.get(owner_id=active_user.id)

    assert len(bytes(rec.blob)) in set(ENVELOPE_BUCKETS)
    # A pure date, never a timestamp (datetime is a subclass of date, so exclude it).
    assert isinstance(rec.stored_date, datetime.date)
    assert not isinstance(rec.stored_date, datetime.datetime)
