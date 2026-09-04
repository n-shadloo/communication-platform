"""What a socket's bind waits for while a send holds its device row.

The seam decision behind this file is ADR-0005: a WebSocket scope enters no
`ThreadSensitiveContext`, so every socket's ORM unit runs on the one
process-wide thread-sensitive executor thread. That makes any wait inside a
gateway unit a wait for every socket in the worker, not for one of them.

`send` locks each live target device with `SELECT ... FOR UPDATE` and holds it to
commit (ADR-0017), and `_touch_active` writes the same row. So the two contend on
exactly the device a send is delivering to — the device most likely to be
reconnecting.
"""

import threading
import time
import uuid

import pytest
from django.db import connections, transaction
from django.utils import timezone

from devices.models import Device
from realtime.auth import _touch_active

pytestmark = pytest.mark.django_db(transaction=True)

# Long enough to measure against a wait of microseconds, short enough that a
# regression costs one second rather than a hung suite.
HOLD_SECONDS = 1.0
# The wait that says the update queued behind the lock rather than passing it.
BLOCKED_SECONDS = HOLD_SECONDS / 2


class Sender:
    """A thread holding the lock `send` holds, in the statement `send` uses."""

    def __init__(self, device_id):
        self.device_id = device_id
        self.holding = threading.Event()
        self.release = threading.Event()
        self._thread = threading.Thread(target=self._hold)

    def _hold(self):
        try:
            with transaction.atomic():
                list(
                    Device.objects.select_for_update(of=("self",))
                    .filter(id=self.device_id)
                    .only("id", "queue_seq")
                    .order_by("id")
                )
                self.holding.set()
                self.release.wait(HOLD_SECONDS)
        finally:
            connections.close_all()

    def __enter__(self):
        self._thread.start()
        assert self.holding.wait(HOLD_SECONDS), "the lock was never taken"
        return self

    def __exit__(self, *_exc):
        self.release.set()
        self._thread.join(HOLD_SECONDS * 2)


def elapsed(call):
    began = time.perf_counter()
    call()
    return time.perf_counter() - began


def test_a_bind_on_a_device_a_send_is_locking_does_not_queue_behind_it(device):
    """The bind of a device that has already been seen today writes nothing, so
    it never reaches the lock. Before this, every bind issued an unconditional
    `UPDATE` and waited out the send — on the one thread every socket shares."""
    Device.objects.filter(id=device.id).update(last_active_date=timezone.now().date())

    with Sender(device.id):
        waited = elapsed(lambda: _touch_active(device.id))

    assert waited < BLOCKED_SECONDS, f"the bind queued behind the send for {waited:.3f}s"


def test_the_first_bind_of_the_day_still_records_it(device):
    """The write is skipped only because the row already says today. A device
    whose date is stale, or that has never connected, still gets one."""
    assert device.last_active_date is None

    _touch_active(device.id)
    device.refresh_from_db()
    assert device.last_active_date == timezone.now().date()

    Device.objects.filter(id=device.id).update(
        last_active_date=timezone.now().date() - timezone.timedelta(days=1)
    )
    _touch_active(device.id)
    device.refresh_from_db()
    assert device.last_active_date == timezone.now().date()


def test_two_binds_of_one_device_race_without_deadlocking(device):
    """Two sockets of one device reconnecting at once — a phone waking while a
    laptop resumes — run this unit on two connections against one row. Both are
    conditional updates of that row, so the second waits out the first's row lock
    and neither is chosen as a deadlock victim."""
    failures = []

    def bind():
        try:
            _touch_active(device.id)
        except Exception as failure:  # the race is the point: record, never raise
            failures.append(failure)
        finally:
            connections.close_all()

    threads = [threading.Thread(target=bind) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(HOLD_SECONDS * 2)

    assert failures == []
    device.refresh_from_db()
    assert device.last_active_date == timezone.now().date()


def test_a_bind_for_a_device_that_is_gone_writes_nothing(device):
    """The row can be deleted between the token check and the stamp — a revoke
    that lands mid-bind. The filter then matches nothing, which is a write of zero
    rows rather than an error the socket has to survive."""
    _touch_active(uuid.uuid4())

    device.refresh_from_db()
    assert device.last_active_date is None
