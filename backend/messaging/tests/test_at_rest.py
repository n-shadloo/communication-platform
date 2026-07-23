"""What a seized `messaging_queuedenvelope` table yields: fan-out must leave N
independent rows that a dump cannot join back into a conversation.

`transaction=True` matters on these tests: pg_dump runs in a separate process over a
separate connection, so it sees only committed rows.
"""
from datetime import datetime
from datetime import timezone as dt_timezone

import pytest

from accounts.models import User
from accounts.tests.test_at_rest import PG_DUMP, pg_dump_table
from core.buckets import ENVELOPE_BUCKETS

from .conftest import PASSWORD, envelope_blob, make_device

TABLE = "messaging_queuedenvelope"

# The routing minimum and nothing else. A column added here fails this test on purpose.
EXPECTED_COLUMNS = {"id", "recipient_device_id", "seq", "blob", "queued_hour"}


def copy_block(dump, table):
    """Parse pg_dump's COPY block into (column names, row dicts)."""
    lines = dump.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(f"COPY public.{table} "):
            cols = line[line.index("(") + 1:line.index(")")].split(", ")
            rows = []
            for raw in lines[i + 1:]:
                if raw == "\\.":
                    break
                rows.append(dict(zip(cols, raw.split("\t"))))
            return cols, rows
    raise AssertionError(f"no COPY block for {table} in the dump")


@pytest.fixture
def three_recipient_devices(db):
    bob = User.objects.create_user(username="bob", password=PASSWORD, is_active=True)
    carol = User.objects.create_user(username="carol", password=PASSWORD, is_active=True)
    return [make_device(bob, 11), make_device(bob, 12), make_device(carol, 21)]


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_a_seized_queue_shows_no_sender_and_no_link_between_co_recipients(
        api, active_user, device, auth_headers, three_recipient_devices):
    # One logical message to 3 devices across 2 users; a real client encrypts per
    # device, so the three copies differ.
    resp = api.post("/api/v1/envelopes", {"messages": [
        {"device_id": str(d.id), "blob": envelope_blob(bytes([65 + i]))}
        for i, d in enumerate(three_recipient_devices)
    ]}, format="json", **auth_headers(active_user, device))
    assert resp.status_code == 202

    cols, rows = copy_block(pg_dump_table(TABLE), TABLE)

    # (a) No sender column exists — sender identity lives only inside the ciphertext.
    assert [c for c in cols if "sender" in c.lower()] == []
    assert set(cols) == EXPECTED_COLUMNS, "the queue grew a column it must not have"

    # (b) Three independent rows. The only thing tying a row to anyone is its own
    # recipient device; no shared row id and no shared blob to join co-recipients on.
    # `seq` and `queued_hour` coincide across the three rows by design: seq is
    # per-device (every fresh mailbox starts at 1) and the hour is deliberately coarse.
    # Neither links co-recipients; a third party's row would carry the same values.
    assert len(rows) == 3
    assert len({r["recipient_device_id"] for r in rows}) == 3
    assert len({r["id"] for r in rows}) == 3
    assert len({r["blob"] for r in rows}) == 3

    # (c) Every stored blob is exactly one bucket long. pg_dump renders bytea as \x<hex>,
    # backslash-escaped again by the COPY text format.
    for row in rows:
        hexed = row["blob"].lstrip("\\")
        assert hexed.startswith("x"), f"unexpected bytea rendering: {hexed[:8]}"
        assert len(hexed[1:]) // 2 in set(ENVELOPE_BUCKETS)

    # (d) Nothing finer than the hour is recorded. pg_dump renders timestamptz in the
    # session's timezone, which need not be UTC (a +03:30 offset renders as :30), so
    # normalise before asserting rather than reading the wall clock.
    for row in rows:
        stamp = datetime.fromisoformat(row["queued_hour"]).astimezone(dt_timezone.utc)
        assert (stamp.minute, stamp.second, stamp.microsecond) == (0, 0, 0), (
            f"timestamp is finer than the hour: {stamp.isoformat()}")

    # The sender is in none of it: alice sent all three and appears nowhere.
    dump = pg_dump_table(TABLE)
    assert str(active_user.id) not in dump
    assert str(device.id) not in dump


@pytest.mark.django_db
def test_the_model_declares_no_sender_or_recipient_list_field():
    """The schema half of the same guard, so a regression fails fast without pg_dump."""
    from messaging.models import QueuedEnvelope

    names = {f.name for f in QueuedEnvelope._meta.get_fields()}

    assert names == {"id", "recipient_device", "seq", "blob", "queued_hour"}
    assert not any("sender" in n for n in names)
