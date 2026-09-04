"""The units of work behind the messaging routes, and the live push behind the
durable mailbox.

The push is the one piece that is not a unit of work: it runs after the send unit
has committed, it is awaited on the loop rather than on the ORM thread, and it can
never fail the request.
"""

import base64

from django.db import transaction

from devices.models import Device
from messaging.models import QueuedEnvelope
from realtime import bus


def _b64(raw):
    return base64.b64encode(bytes(raw)).decode()


def send(messages):
    """One send call is one transaction.

    One statement locks every live target, and its `ORDER BY id` is what fixes the
    order the rows are taken in — PostgreSQL puts the lock step above the sort — so
    two batches that name the same recipients in opposite orders queue behind each
    other instead of deadlocking. Each lock is held to commit, which is what keeps
    `(recipient_device, seq)` unique with no global sequence. `of=("self",)` keeps
    the lock off the account rows the liveness filter joins; taking those too would
    contend with the account-row lock registration and the device log hold.

    Returns the accepted rows, in the order the batch named them, and the ids the
    batch could not reach.
    """
    wanted = sorted({message.device_id for message in messages})  # one id per device
    with transaction.atomic():
        targets = {
            device.id: device
            for device in Device.objects.select_for_update(of=("self",))
            .filter(id__in=wanted, revoked_date__isnull=True, user__is_active=True)
            .only("id", "queue_seq")
            .order_by("id")
        }
        stale = []
        rows = []
        for message in messages:
            device = targets.get(message.device_id)
            if device is None:
                stale.append(str(message.device_id))
                continue
            device.queue_seq += 1
            rows.append(
                QueuedEnvelope(
                    recipient_device_id=device.id,
                    seq=device.queue_seq,
                    blob=message.raw,
                )
            )
        # Both are no-ops on an empty list, so a batch that reached nothing live
        # costs no write query at all.
        Device.objects.bulk_update(targets.values(), ["queue_seq"])
        QueuedEnvelope.objects.bulk_create(rows)
    return rows, stale


async def push(envelopes):
    """Best-effort live delivery over the fan-out bus.

    Called after `send` has committed, never inside it: a publish from an open
    transaction would announce rows a rollback then takes away. Redis drops a
    publish to a topic nobody holds, so a device without a socket is a no-op.

    The queue rows are the source of truth and are already committed, so a bus
    that is down must not fail the send — the client would retry and duplicate
    every envelope. `realtime.bus.publish` is what swallows that, silently,
    because the message would carry a device id.
    """
    for envelope in envelopes:
        await bus.push_envelope(
            envelope.recipient_device_id,
            str(envelope.id),
            envelope.seq,
            _b64(envelope.blob),
        )


def drain(device_id, limit):
    rows = list(
        QueuedEnvelope.objects.filter(recipient_device_id=device_id)
        .order_by("seq")
        .only("id", "seq", "blob")[: limit + 1]
    )
    has_more = len(rows) > limit
    return [
        {"id": str(row.id), "seq": row.seq, "blob": _b64(row.blob)}
        for row in rows[:limit]
    ], has_more


def ack(device_id, ids):
    """Filtered by the calling device, so an id from another mailbox matches
    nothing, and a second call for the same id deletes nothing."""
    deleted, _ = QueuedEnvelope.objects.filter(
        recipient_device_id=device_id, id__in=ids
    ).delete()
    return {"deleted": deleted}
