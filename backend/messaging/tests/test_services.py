"""The units of work behind the messaging routes, called directly.

Three of the four functions here are one transaction each, and what they leave
behind is a row, a count, or a list the route renders. Driving them without a
request is what makes the return values observable at the point the unit produces
them — the route only ever shows the client a projection of these — and it is the
only way to reach the arguments the schema layer keeps a request from carrying:
an empty batch, a page size of zero.

`push` is the one that is not a unit of work. It runs after the send has
committed, on the event loop rather than the ORM thread, and the only thing it
can be observed by is a subscriber on the bus.
"""

import base64
import uuid

import pytest
from asgiref.sync import async_to_sync
from django.utils import timezone

from devices.models import Device
from messaging import services
from messaging.models import QueuedEnvelope
from messaging.schemas import OutgoingItemIn
from realtime import bus

from .conftest import SMALLEST_BUCKET, envelope_blob, make_device
from .test_push import Listener

pytestmark = pytest.mark.django_db(transaction=True)


def outgoing(device_id, filler=b"a"):
    return OutgoingItemIn(device_id=str(device_id), blob=envelope_blob(filler))


def enqueue(device, count, start=1):
    return [
        QueuedEnvelope.objects.create(
            recipient_device=device, seq=start + i, blob=bytes([97 + i]) * SMALLEST_BUCKET
        )
        for i in range(count)
    ]


class TestSend:
    def test_every_accepted_item_comes_back_paired_with_the_base64_its_sender_sent(
        self, bob_devices
    ):
        """The push needs exactly that string, and re-deriving it from the stored
        bytes costs a second pass over every blob on the event loop."""
        target = bob_devices[0]
        message = outgoing(target.id, b"p")

        accepted, stale, full = services.send([message])

        assert (stale, full) == ([], [])
        row, blob = accepted[0]
        assert blob == message.blob
        assert bytes(row.blob) == base64.b64decode(message.blob)

    def test_the_accepted_rows_keep_the_order_the_batch_named_them_in(self, bob, carol):
        """The lock is taken in id order, but what comes back is the batch's own
        order: the live push must announce a device's copies in the sequence the
        sender wrote them."""
        targets = [make_device(bob, 141), make_device(bob, 142), make_device(carol, 143)]
        ordered = sorted(targets, key=lambda one: str(one.id), reverse=True)

        accepted, _stale, _full = services.send(
            [outgoing(one.id, bytes([65 + i])) for i, one in enumerate(ordered)]
        )

        assert [row.recipient_device_id for row, _blob in accepted] == [
            one.id for one in ordered
        ]

    def test_an_empty_batch_is_a_no_op_that_writes_nothing(self, bob_devices):
        """Unreachable through the route, which refuses a batch below one item, so
        the unit is the only place the boundary can be shown at all."""
        assert services.send([]) == ([], [], [])
        assert QueuedEnvelope.objects.count() == 0

    def test_an_unknown_device_is_reported_stale_as_a_string_the_client_can_match(
        self,
    ):
        ghost = uuid.uuid4()

        accepted, stale, full = services.send([outgoing(ghost)])

        assert (accepted, stale, full) == ([], [str(ghost)], [])

    def test_a_full_mailbox_is_named_and_its_counter_never_moves(
        self, bob_devices, settings
    ):
        settings.MAILBOX_MAX_BYTES = SMALLEST_BUCKET
        target = bob_devices[0]
        enqueue(target, 1)
        target.queue_seq = 1
        target.save(update_fields=["queue_seq"])

        accepted, stale, full = services.send([outgoing(target.id, b"F")])

        assert (accepted, stale) == ([], [])
        assert full == [str(target.id)]
        target.refresh_from_db()
        assert target.queue_seq == 1

    def test_the_full_list_is_ordered_so_two_identical_batches_answer_identically(
        self, bob, settings
    ):
        """`stale` follows the batch, but `full` is derived from a set, and a set
        of UUIDs iterates in an order the hash seed decides — an unsorted list here
        would make the response body differ between two processes."""
        settings.MAILBOX_MAX_BYTES = 1
        targets = [make_device(bob, 151), make_device(bob, 152), make_device(bob, 153)]

        _accepted, _stale, full = services.send([outgoing(one.id) for one in targets])

        assert full == sorted(str(one.id) for one in targets)

    def test_the_same_device_named_twice_takes_two_consecutive_sequence_numbers(
        self, bob_devices
    ):
        """One id per device is locked, but each item is still its own row: the
        counter advances inside the loop rather than once per device."""
        target = bob_devices[0]

        accepted, _stale, _full = services.send(
            [outgoing(target.id, b"a"), outgoing(target.id, b"b")]
        )

        assert [row.seq for row, _blob in accepted] == [1, 2]
        target.refresh_from_db()
        assert target.queue_seq == 2

    def test_a_batch_that_reached_nothing_live_leaves_every_counter_where_it_was(
        self, bob_devices
    ):
        dead, alive = bob_devices
        dead.revoked_date = timezone.now().date()
        dead.save(update_fields=["revoked_date"])

        accepted, stale, _full = services.send([outgoing(dead.id)])

        assert (accepted, stale) == ([], [str(dead.id)])
        assert Device.objects.filter(queue_seq__gt=0).count() == 0
        assert alive.queue_seq == 0


class TestDrain:
    def test_an_empty_mailbox_drains_to_nothing_with_no_further_page(self, device):
        assert services.drain(device.id, 100) == ([], False)

    def test_the_page_is_ordered_by_seq_whatever_order_the_rows_were_written_in(
        self, device
    ):
        """The mailbox is an ordered log to the client, and insertion order is not
        it: a device that lost a row to a failed ack and re-received it later would
        otherwise read its own history out of order."""
        for seq in (3, 1, 2):
            QueuedEnvelope.objects.create(
                recipient_device=device, seq=seq, blob=bytes([96 + seq]) * SMALLEST_BUCKET
            )

        envelopes, has_more = services.drain(device.id, 100)

        assert [one["seq"] for one in envelopes] == [1, 2, 3]
        assert has_more is False

    def test_the_blob_comes_back_as_the_base64_of_exactly_what_was_stored(self, device):
        row = enqueue(device, 1)[0]

        envelopes, _has_more = services.drain(device.id, 100)

        assert base64.b64decode(envelopes[0]["blob"]) == bytes(row.blob)
        assert envelopes[0]["id"] == str(row.id)

    @pytest.mark.parametrize(
        "held, limit, page, has_more",
        [(1, 1, 1, False), (2, 1, 1, True), (3, 5, 3, False)],
    )
    def test_the_further_page_flag_turns_over_exactly_at_the_page_size(
        self, device, held, limit, page, has_more
    ):
        """One row past the page is read to decide it, and only that one: the flag
        must not cost a count of the whole mailbox."""
        enqueue(device, held)

        envelopes, flag = services.drain(device.id, limit)

        assert (len(envelopes), flag) == (page, has_more)

    def test_a_page_size_of_zero_returns_nothing_and_still_reports_a_further_page(
        self, device
    ):
        """The boundary the route cannot reach: `clamp_limit` never yields zero, so
        a client polling `?limit=0` pages at one rather than spinning on an empty
        page that claims there is more."""
        enqueue(device, 2)

        assert services.drain(device.id, 0) == ([], True)


class TestAck:
    def test_the_named_rows_go_and_the_count_is_what_the_delete_removed(self, device):
        rows = enqueue(device, 3)

        assert services.ack(device.id, [rows[0].id, rows[2].id]) == {"deleted": 2}
        assert list(QueuedEnvelope.objects.values_list("id", flat=True)) == [rows[1].id]

    def test_an_id_named_twice_in_one_call_is_deleted_once(self, device):
        """`id__in` is a set to the database, so the count reports rows and not
        arguments — a client that retried inside its own batch is told the truth."""
        row = enqueue(device, 1)[0]

        assert services.ack(device.id, [row.id, row.id]) == {"deleted": 1}

    def test_an_id_from_another_mailbox_matches_nothing(self, device, bob_devices):
        victim = enqueue(bob_devices[0], 1)[0]

        assert services.ack(device.id, [victim.id]) == {"deleted": 0}
        assert QueuedEnvelope.objects.filter(id=victim.id).exists()

    def test_an_empty_ack_deletes_nothing_and_leaves_the_mailbox_whole(self, device):
        enqueue(device, 2)

        assert services.ack(device.id, []) == {"deleted": 0}
        assert QueuedEnvelope.objects.count() == 2


class TestPush:
    def test_a_committed_copy_reaches_its_own_device_topic_and_no_other(
        self, bob_devices, settings
    ):
        """The frame is what a socket would have received, so it is asserted whole:
        a key more would be a field the gateway forwards without a contract, and a
        key less would be an envelope the client cannot ack."""
        target, bystander = bob_devices
        row = enqueue(target, 1)[0]
        blob = envelope_blob(b"p")

        with Listener(settings.REDIS_URL, bus.device_topic(target.id)) as subscriber:
            with Listener(
                settings.REDIS_URL, bus.device_topic(bystander.id)
            ) as uninvolved:
                async_to_sync(services.push)([(row, blob)])
                frame = subscriber.receive()

                assert uninvolved.received_nothing()

        assert frame == {
            "type": "envelope",
            "id": str(row.id),
            "seq": row.seq,
            "blob": blob,
        }

    def test_a_send_that_accepted_nothing_publishes_nothing_at_all(
        self, bob_devices, settings
    ):
        """A batch that reached only stale or full devices still calls this, so an
        empty fan-out has to cost no frame — and, in the bus, no round trip."""
        target = bob_devices[0]

        with Listener(settings.REDIS_URL, bus.device_topic(target.id)) as subscriber:
            async_to_sync(services.push)([])

            assert subscriber.received_nothing()
