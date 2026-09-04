"""Per-device `seq` assignment is atomic under concurrency.

`transaction=True` because the point is real committed transactions racing each
other: the enqueue rests on the row lock that `SELECT ... FOR UPDATE` holds until
commit, which a wrapping test transaction would hide.
"""

import threading

import pytest
from django.db import connection, connections

from devices.models import Device
from messaging.models import QueuedEnvelope

from .conftest import envelope_blob, make_device

pytestmark = pytest.mark.django_db(transaction=True)

CONCURRENT_SENDS = 12
SEND_URL = "/api/v1/envelopes"


def connect_then_wait(barrier):
    """Open this thread's database connection before it waits at the barrier.

    Connection setup costs 10-20 ms and varies by thread — more than the whole
    transaction this test is about — so threads released together would otherwise
    reach the row one at a time on a slow runner, and what the guard proves would
    depend on the machine instead of on the lock.
    """
    connection.ensure_connection()
    barrier.wait(timeout=10)


def test_concurrent_sends_to_one_device_never_collide_or_gap(
    new_http, active_user, device, bearer, bob
):
    target = make_device(bob, 2)
    headers = bearer(active_user, device)
    failures = []
    # A barrier so the workers contend on the same row instead of trickling through.
    start = threading.Barrier(CONCURRENT_SENDS)

    def send():
        try:
            connect_then_wait(start)
            resp = new_http().post(
                SEND_URL,
                json={
                    "messages": [{"device_id": str(target.id), "blob": envelope_blob()}]
                },
                headers=headers,
            )
            if resp.status_code != 202:
                failures.append(resp.status_code)
        except Exception as exc:  # a seq collision surfaces as IntegrityError → 500
            failures.append(repr(exc))
        finally:
            connections.close_all()

    threads = [threading.Thread(target=send) for _ in range(CONCURRENT_SENDS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)

    assert failures == []
    seqs = sorted(
        QueuedEnvelope.objects.filter(recipient_device_id=target.id).values_list(
            "seq", flat=True
        )
    )
    # Unique (no lost update) and gapless (nothing reserved then dropped), so the
    # mailbox orders deterministically.
    assert seqs == list(range(1, CONCURRENT_SENDS + 1))
    assert Device.objects.get(id=target.id).queue_seq == CONCURRENT_SENDS


def test_two_batches_with_overlapping_recipients_never_deadlock(
    new_http, active_user, device, bearer, bob
):
    """The lock order is what keeps this safe. Two batches that named the same two
    devices in opposite orders would take the rows in opposite orders and one of
    them would die with a deadlock, so the unit sorts the ids before it locks."""
    first, second = make_device(bob, 3), make_device(bob, 4)
    headers = bearer(active_user, device)
    failures = []
    start = threading.Barrier(2)

    def send(order):
        try:
            connect_then_wait(start)
            resp = new_http().post(
                SEND_URL,
                json={
                    "messages": [
                        {"device_id": str(d.id), "blob": envelope_blob()} for d in order
                    ]
                },
                headers=headers,
            )
            if resp.status_code != 202:
                failures.append(resp.status_code)
        except Exception as exc:  # a deadlock surfaces as OperationalError → 500
            failures.append(repr(exc))
        finally:
            connections.close_all()

    threads = [
        threading.Thread(target=send, args=(order,))
        for order in ([first, second], [second, first])
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)

    assert failures == []
    for target in (first, second):
        assert QueuedEnvelope.objects.filter(recipient_device_id=target.id).count() == 2


def test_the_unique_constraint_would_catch_a_duplicate_seq(bob):
    """Guards the guard: without this, the tests above could pass vacuously if the
    constraint were ever dropped."""
    target = make_device(bob, 5)
    QueuedEnvelope.objects.create(recipient_device=target, seq=1, blob=b"a" * 1024)

    with pytest.raises(Exception):
        QueuedEnvelope.objects.create(recipient_device=target, seq=1, blob=b"b" * 1024)
