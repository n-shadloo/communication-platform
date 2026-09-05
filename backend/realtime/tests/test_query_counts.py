"""Pins the query count of every DB touch the gateway can make.

Each unit of work is measured as the synchronous function it is, not through the
`async` wrapper beside it: the async boundary is exercised by the live socket
tests, and `run_unit`'s `close_old_connections` bracket would sever this test's
own transaction under CONN_MAX_AGE=0 — Django closes a connection whose
autocommit flag disagrees with its settings, which inside pytest-django's atomic
block is every connection, and the reopen then fails with "Cannot open a new
connection in an atomic block"."""

import uuid

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext

from api.auth import issue_full, issue_register_scope
from core.buckets import ENVELOPE_BUCKETS
from messaging.models import QueuedEnvelope
from realtime.auth import _authenticate_access, _delete_envelopes, _touch_active

pytestmark = pytest.mark.django_db

TXN_BOOKKEEPING = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE SAVEPOINT")


def _count(unit, *args):
    with CaptureQueriesContext(connection) as ctx:
        unit(*args)
    return [q["sql"] for q in ctx.captured_queries]


def test_authenticate_access_is_one_joined_query(active_user, device):
    """Device and user in one SELECT via select_related: the socket's auth is one
    query cheaper than REST's two-step lookup."""
    access, _ = issue_full(active_user, device)

    queries = _count(_authenticate_access, access)

    assert len(queries) == 1
    assert "JOIN" in queries[0]


def test_touch_active_is_one_update(device):
    queries = _count(_touch_active, device.id)

    assert len(queries) == 1
    assert queries[0].startswith("UPDATE")


def test_ack_delete_is_one_statement(active_user, device):
    """One DELETE regardless of ack size (fast-delete path; the BEGIN/COMMIT pair is
    Django's own atomic wrapper, not extra round-trip work)."""
    rows = QueuedEnvelope.objects.bulk_create(
        [
            QueuedEnvelope(
                recipient_device=device, seq=i + 1, blob=b"e" * min(ENVELOPE_BUCKETS)
            )
            for i in range(200)
        ]
    )

    queries = _count(_delete_envelopes, device.id, [r.id for r in rows])

    deletes = [q for q in queries if q.startswith("DELETE")]
    assert len(deletes) == 1
    assert all(
        q.startswith(TXN_BOOKKEEPING) for q in queries if not q.startswith("DELETE")
    )
    assert QueuedEnvelope.objects.filter(recipient_device=device).count() == 0


def test_a_bind_costs_the_token_check_and_the_activity_stamp(active_user, device):
    """The whole database cost of bringing a socket up: one joined read to verify
    the token, one UPDATE to stamp the device active. Nothing here may grow with
    the mailbox or the account's device count, because it runs on every reconnect
    of every client."""
    access, _ = issue_full(active_user, device)

    queries = _count(_authenticate_access, access) + _count(_touch_active, device.id)

    assert len(queries) == 2


def test_a_token_that_fails_verification_costs_no_query_at_all(db):
    """Signature and expiry are settled in memory, before anything is looked up. A
    flood of garbage tokens against `/ws` is otherwise a flood of device lookups on
    the one thread every socket of the worker shares."""
    assert _count(_authenticate_access, "not-a-jwt") == []


def test_a_register_scope_token_never_reaches_the_device_row(active_user):
    """Scope is checked before the lookup, so the endpoint a register token does
    not open costs it nothing to be refused from — and the refusal cannot be timed
    against a device row that may or may not exist."""
    token = issue_register_scope(active_user)

    assert _count(_authenticate_access, token) == []


def test_an_ack_naming_rows_that_are_not_there_is_still_one_statement(device):
    """Ids outside this device's mailbox match nothing, which is the documented
    answer for a duplicate ack and for an id from another device. It must not
    become a lookup for each id."""
    queries = _count(_delete_envelopes, device.id, [uuid.uuid4() for _ in range(50)])

    deletes = [q for q in queries if q.startswith("DELETE")]
    assert len(deletes) == 1
    assert all(
        q.startswith(TXN_BOOKKEEPING) for q in queries if not q.startswith("DELETE")
    )
