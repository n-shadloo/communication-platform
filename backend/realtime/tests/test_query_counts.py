"""Pins the query count of every DB touch the consumer can make (§A6: each is a single
statement, wrapped for the event loop). Each helper's *underlying* sync function
(`.func`) is measured directly: the async boundary is exercised by the live consumer
tests, and `database_sync_to_async`'s close_old_connections would sever the test
transaction's connection under CONN_MAX_AGE=0."""
import pytest
from django.test.utils import CaptureQueriesContext
from django.db import connection

from accounts.tokens import issue_full
from core.buckets import ENVELOPE_BUCKETS
from messaging.models import QueuedEnvelope

from realtime.auth import authenticate_access, delete_envelopes, touch_active

pytestmark = pytest.mark.django_db

TXN_BOOKKEEPING = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE SAVEPOINT")


def _count(wrapped, *args):
    with CaptureQueriesContext(connection) as ctx:
        wrapped.func(*args)
    return [q["sql"] for q in ctx.captured_queries]


def test_authenticate_access_is_one_joined_query(active_user, device):
    """Device + user in one SELECT via select_related — the socket's auth is actually
    one query cheaper than REST's two-step lookup (§A8 parity, better plan)."""
    access, _ = issue_full(active_user, device)

    queries = _count(authenticate_access, access)

    assert len(queries) == 1
    assert "JOIN" in queries[0]


def test_touch_active_is_one_update(device):
    queries = _count(touch_active, device.id)

    assert len(queries) == 1
    assert queries[0].startswith("UPDATE")


def test_ack_delete_is_one_statement(active_user, device):
    """One DELETE regardless of ack size (fast-delete path; the BEGIN/COMMIT pair is
    Django's own atomic wrapper, not extra round-trip work)."""
    rows = QueuedEnvelope.objects.bulk_create(
        [QueuedEnvelope(recipient_device=device, seq=i + 1,
                        blob=b"e" * min(ENVELOPE_BUCKETS)) for i in range(200)])

    queries = _count(delete_envelopes, device.id, [r.id for r in rows])

    deletes = [q for q in queries if q.startswith("DELETE")]
    assert len(deletes) == 1
    assert all(q.startswith(TXN_BOOKKEEPING) for q in queries
               if not q.startswith("DELETE"))
    assert QueuedEnvelope.objects.filter(recipient_device=device).count() == 0
