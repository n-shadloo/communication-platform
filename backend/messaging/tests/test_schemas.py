"""The inbound and outbound models of the messaging surface, without a request.

Every messaging body reaches these classes before it reaches a unit of work, so
the shape refusals belong here; what the routes add on top is the envelope, and
`messaging/tests/test_routes.py` is where that is proven. Nothing here touches
the database: a `device_id` is parsed, never looked up.

`clamp_limit` is the one function of this module that is not a model, and the one
the client polls. It never raises and never refuses — a stale client sending a
value this server does not like must not be locked out of its own mailbox — so
what it needs is a table of what each answer clamps to, both ends included.
"""

import base64
import uuid

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic import ValidationError

from core.buckets import ENVELOPE_BUCKETS
from core.fields import BadBucket
from messaging.schemas import (
    MAX_ACK_IDS,
    MAX_BLOB_CHARS,
    MAX_DRAIN_LIMIT,
    MAX_SEND_BATCH,
    AckIn,
    AckOut,
    DrainOut,
    EnvelopeOut,
    OutgoingItemIn,
    SendIn,
    SendOut,
    clamp_limit,
)

SMALLEST_BUCKET = min(ENVELOPE_BUCKETS)


def b64_of(nbytes, fill=b"\x11"):
    return base64.b64encode(fill * nbytes).decode()


def error_types(exc_info):
    return {error["type"] for error in exc_info.value.errors()}


def error_fields(exc_info):
    return {
        ".".join(str(part) for part in error["loc"]) for error in exc_info.value.errors()
    }


def item(**overrides):
    body = {"device_id": str(uuid.uuid4()), "blob": b64_of(SMALLEST_BUCKET)}
    body.update(overrides)
    return body


class TestClampLimit:
    @pytest.mark.parametrize(
        "raw, clamped",
        [
            ("1", 1),
            ("2", 2),
            ("99", 99),
            ("100", MAX_DRAIN_LIMIT),
            ("101", MAX_DRAIN_LIMIT),
            ("0", 1),
            ("-5", 1),
            ("abc", MAX_DRAIN_LIMIT),
            ("", MAX_DRAIN_LIMIT),
            (None, MAX_DRAIN_LIMIT),
            ("1e3", MAX_DRAIN_LIMIT),
            ("3.7", MAX_DRAIN_LIMIT),
            (" 7 ", 7),
        ],
    )
    def test_the_published_clamp_holds_at_both_ends_and_outside_them(self, raw, clamped):
        assert clamp_limit(raw) == clamped

    def test_a_number_longer_than_python_will_parse_falls_back_to_the_cap(self):
        """The rare one. CPython refuses `int()` on a decimal string past 4300
        digits, so the guard has to be the same `ValueError` arm that catches
        `"abc"` rather than a digit check that would let this through."""
        assert clamp_limit("9" * 10_000) == MAX_DRAIN_LIMIT

    @pytest.mark.parametrize("raw", [{}, [], object(), b"not-a-number"])
    def test_a_value_that_is_not_a_number_at_all_still_answers_the_cap(self, raw):
        """The parameter arrives as a string from the query, but the function is
        the route's only guard: anything it cannot read is the cap, never a
        raise."""
        assert clamp_limit(raw) == MAX_DRAIN_LIMIT

    @settings(max_examples=100)
    @given(st.text(alphabet="0123456789-+ eE.x", max_size=12))
    def test_no_query_value_can_make_the_page_size_leave_its_bounds(self, raw):
        """The property the drain rests on: the value that reaches the slice is
        always a positive integer no larger than the cap, whatever was polled."""
        clamped = clamp_limit(raw)

        assert isinstance(clamped, int)
        assert 1 <= clamped <= MAX_DRAIN_LIMIT


class TestOutgoingItemIn:
    @pytest.mark.parametrize("bucket", ENVELOPE_BUCKETS)
    def test_a_bucket_sized_blob_decodes_to_its_raw_bytes(self, bucket):
        parsed = OutgoingItemIn(**item(blob=b64_of(bucket)))

        assert parsed.raw == b"\x11" * bucket

    @pytest.mark.parametrize(
        "size",
        [
            1,
            SMALLEST_BUCKET - 1,
            SMALLEST_BUCKET + 1,
            max(ENVELOPE_BUCKETS) - 1,
            max(ENVELOPE_BUCKETS) + 1,
        ],
    )
    def test_an_off_bucket_blob_is_a_bad_bucket_and_not_a_validation_error(self, size):
        with pytest.raises(BadBucket):
            OutgoingItemIn(**item(blob=b64_of(size)))

    @pytest.mark.parametrize(
        "blob",
        [
            "definitely not base64 !!",
            "q83vEjRWeJ",  # length is not a multiple of four
            "_" * 1368,  # the URL-safe alphabet, which the strict decoder refuses
            "A" * 1367 + "\x00",
        ],
    )
    def test_a_blob_that_is_not_strict_base64_is_a_bad_bucket(self, blob):
        with pytest.raises(BadBucket):
            OutgoingItemIn(**item(blob=blob))

    def test_the_longest_blob_string_the_field_admits_is_still_bucket_checked(self):
        """The cap is headroom for the largest bucket plus padding, never a second
        bucket: what it admits still has to land on an exact length."""
        blob = b64_of(262152)

        assert len(blob) == MAX_BLOB_CHARS
        with pytest.raises(BadBucket):
            OutgoingItemIn(**item(blob=blob))

    def test_one_character_more_is_refused_before_the_decode(self):
        """Without the cap an arbitrarily long string reaches `b64decode`, which
        would allocate three quarters of it before deciding anything."""
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(**item(blob="A" * (MAX_BLOB_CHARS + 1)))

        assert error_types(exc_info) == {"string_too_long"}

    def test_an_empty_blob_is_refused_by_the_field_rather_than_the_bucket_set(self):
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(**item(blob=""))

        assert error_types(exc_info) == {"string_too_short"}

    def test_a_missing_device_id_is_a_validation_error_rather_than_a_bad_bucket(self):
        """The decode is an after-validator, so it runs only once every field has
        validated: a body that is both malformed and off-bucket reports the field,
        because `BadBucket` carries no field path at all."""
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(blob=b64_of(SMALLEST_BUCKET - 1))

        assert error_fields(exc_info) == {"device_id"}

    def test_a_uuid_arrives_as_a_uuid_however_the_client_spells_it(self):
        """Lax UUID is what admits a string at all — strict mode there takes only
        a `uuid.UUID` instance, which JSON cannot carry. Every spelling Python
        accepts normalises to one value, so no spelling reaches a second mailbox
        of its own."""
        device_id = uuid.uuid4()
        spellings = [
            str(device_id),
            device_id.hex,
            f"{{{device_id}}}",
            f"urn:uuid:{device_id}",
        ]

        parsed = [OutgoingItemIn(**item(device_id=spelling)) for spelling in spellings]

        assert {one.device_id for one in parsed} == {device_id}

    @pytest.mark.parametrize(
        "device_id",
        [5, 1.5, True, None, ["not-a-uuid"], {}, "not-a-uuid", "", "abc\x00def"],
    )
    def test_a_device_id_that_is_not_a_uuid_is_refused_rather_than_coerced(
        self, device_id
    ):
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(**item(device_id=device_id))

        assert error_fields(exc_info) == {"device_id"}

    @pytest.mark.parametrize("blob", [5, None, ["a"], {"b": 1}, b"AAAA"])
    def test_a_blob_of_the_wrong_type_is_refused_rather_than_coerced(self, blob):
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(**item(blob=blob))

        assert error_fields(exc_info) == {"blob"}

    def test_an_unknown_field_is_refused(self):
        """A `sender` key that were quietly dropped would read to a client author
        as a field this server honours."""
        with pytest.raises(ValidationError) as exc_info:
            OutgoingItemIn(**item(sender="alice"))

        assert error_types(exc_info) == {"extra_forbidden"}

    @settings(max_examples=60)
    @given(
        st.one_of(
            st.sampled_from(ENVELOPE_BUCKETS),
            st.integers(min_value=0, max_value=2 * SMALLEST_BUCKET),
        )
    )
    def test_a_length_decodes_exactly_when_it_is_a_bucket(self, size):
        """Drawn from the buckets and from the range around them, so both answers
        are exercised: whichever the model gives, the length is what decided it."""
        try:
            parsed = OutgoingItemIn(**item(blob=b64_of(size)))
        except (BadBucket, ValidationError):
            assert size not in ENVELOPE_BUCKETS
            return
        assert size in ENVELOPE_BUCKETS
        assert len(parsed.raw) == size


class TestSendIn:
    def test_the_smallest_and_the_largest_batch_are_both_accepted(self):
        smallest = SendIn(messages=[item()])
        largest = SendIn(messages=[item() for _ in range(MAX_SEND_BATCH)])

        assert len(smallest.messages) == 1
        assert len(largest.messages) == MAX_SEND_BATCH

    @pytest.mark.parametrize("count", [0, MAX_SEND_BATCH + 1])
    def test_a_batch_one_step_outside_the_bounds_is_refused(self, count):
        with pytest.raises(ValidationError) as exc_info:
            SendIn(messages=[item() for _ in range(count)])

        assert error_fields(exc_info) == {"messages"}

    @pytest.mark.parametrize("messages", [{}, "a", 5, None, item()])
    def test_a_messages_value_that_is_not_a_list_is_refused(self, messages):
        with pytest.raises(ValidationError) as exc_info:
            SendIn(messages=messages)

        assert error_fields(exc_info) == {"messages"}

    def test_the_failing_item_of_a_batch_is_named_by_its_index(self):
        """A list item carries its position in the path, which is what makes a
        400 on a 256-item batch actionable for the client."""
        with pytest.raises(ValidationError) as exc_info:
            SendIn(messages=[item(), item(device_id="not-a-uuid"), item()])

        assert error_fields(exc_info) == {"messages.1.device_id"}

    def test_an_unknown_field_beside_the_batch_is_refused(self):
        with pytest.raises(ValidationError) as exc_info:
            SendIn(messages=[item()], sender_device_id=str(uuid.uuid4()))

        assert error_types(exc_info) == {"extra_forbidden"}


class TestAckIn:
    def test_a_missing_ids_key_is_an_empty_list_rather_than_a_refusal(self):
        """The published contract: a body with no `ids` acks nothing and answers
        `{"deleted": 0}`, so a client draining an empty mailbox needs no branch."""
        assert AckIn().ids == []

    def test_the_largest_ack_the_field_admits_is_accepted(self):
        ids = [str(uuid.uuid4()) for _ in range(MAX_ACK_IDS)]

        assert len(AckIn(ids=ids).ids) == MAX_ACK_IDS

    def test_one_id_more_is_refused(self):
        with pytest.raises(ValidationError) as exc_info:
            AckIn(ids=[str(uuid.uuid4()) for _ in range(MAX_ACK_IDS + 1)])

        assert error_types(exc_info) == {"too_long"}

    def test_a_duplicate_id_survives_parsing_and_is_left_to_the_delete(self):
        """The model is not a set: deduplication belongs to `id__in`, and a schema
        that silently collapsed the list would hide a client bug rather than
        answer it with the count it actually deleted."""
        one = uuid.uuid4()

        assert AckIn(ids=[str(one), str(one)]).ids == [one, one]

    @pytest.mark.parametrize("ids", ["abc", 5, {}, None, uuid.uuid4()])
    def test_an_ids_value_that_is_not_a_list_is_refused(self, ids):
        with pytest.raises(ValidationError) as exc_info:
            AckIn(ids=ids)

        assert error_fields(exc_info) == {"ids"}

    @pytest.mark.parametrize(
        "bad", ["abc", 123, None, {}, [], "", "../../etc/passwd", "abc\x00def"]
    )
    def test_an_item_that_is_not_a_uuid_is_refused_and_names_its_index(self, bad):
        """Unparsed, these reach a uuid column and raise where nothing turns them
        into anything but a server error."""
        with pytest.raises(ValidationError) as exc_info:
            AckIn(ids=[str(uuid.uuid4()), bad])

        assert error_fields(exc_info) == {"ids.1"}

    def test_the_relaxation_is_on_the_identifier_and_never_on_the_list(self):
        """`strict=False` written on the list would be read as the list's own
        strictness and leave the items strict, which JSON could never satisfy —
        so both spellings a decoded body can carry have to arrive."""
        one, two = uuid.uuid4(), uuid.uuid4()

        parsed = AckIn(ids=[str(one), two])

        assert parsed.ids == [one, two]

    def test_an_unknown_field_is_refused(self):
        with pytest.raises(ValidationError) as exc_info:
            AckIn(ids=[], device_id=str(uuid.uuid4()))

        assert error_types(exc_info) == {"extra_forbidden"}


class TestTheResponseModels:
    def test_the_send_answer_names_counts_and_device_lists_and_nothing_else(self):
        assert set(SendOut.model_fields) == {"accepted", "stale_devices", "full_devices"}

    def test_a_drained_envelope_carries_no_sender_and_no_recipient(self):
        """The response shape is the other half of the at-rest guarantee: a field
        here would be one the row does not hold and the server would have to
        invent."""
        assert set(EnvelopeOut.model_fields) == {"id", "seq", "blob"}
        assert set(DrainOut.model_fields) == {"envelopes", "has_more", "pruned_through"}

    def test_the_ack_answer_is_a_count_and_never_the_ids_it_deleted(self):
        assert set(AckOut.model_fields) == {"deleted"}

    def test_the_drain_answer_serialises_the_watermark_as_a_plain_number(self):
        """`pruned_through` is a seq, so it must survive as an integer rather than
        becoming a string a client would compare lexically."""
        body = DrainOut(envelopes=[], has_more=False, pruned_through=41).model_dump()

        assert body == {"envelopes": [], "has_more": False, "pruned_through": 41}
