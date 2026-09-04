"""The inbound and outbound models of the voice-room surface, without a request.

`RoomNameIn` splits one job across two guards. The `max_length` bound exists so
an arbitrarily long string never reaches `b64decode`, and the *exact* length rule
is `decode_blob_or_400`'s. The two halves answer with different exceptions —
`ValidationError` becomes `400 invalid_request`, `BadBucket` becomes `400
bad_bucket` — so the exception type is the observable that proves which guard
refused a value, and therefore also proves the order they run in.

The outbound models are here for the field sets alone: what a room route may say
is four facts for a read and three for a mint, and a field added to either would
be a new thing this server tells a client about a room.
"""

import base64

import pytest
from hypothesis import example, given
from hypothesis import strategies as st
from pydantic import ValidationError

from core.buckets import NAME_BUCKETS
from core.fields import BadBucket
from voicerooms.schemas import (
    MAX_NAME_CHARS,
    RoomCreatedOut,
    RoomNameIn,
    RoomOut,
    RoomTokenOut,
)

# The bound the surface publishes. Written out rather than recomputed, so a change
# to the formula has to be a deliberate change to this number too.
DOCUMENTED_MAX_CHARS = 1376

# The largest byte count whose base64 still fits under the character bound, so a
# property can range over "everything the length guard lets through".
LARGEST_DECODABLE = 3 * (MAX_NAME_CHARS // 4)


def b64_of(size, filler=b"N"):
    return base64.b64encode(filler * size).decode()


def error_types(exc_info):
    return {error["type"] for error in exc_info.value.errors()}


def error_fields(exc_info):
    return {error["loc"][0] for error in exc_info.value.errors()}


def test_the_character_bound_is_the_one_the_surface_publishes():
    assert MAX_NAME_CHARS == DOCUMENTED_MAX_CHARS


def test_the_bound_admits_the_largest_bucket_with_headroom_to_spare():
    """The normal path of the bound: the biggest legal name must fit under it, or
    the guard meant to stop absurd strings would reject legal ones."""
    largest = b64_of(max(NAME_BUCKETS))

    assert len(largest) <= MAX_NAME_CHARS
    assert RoomNameIn(name_blob=largest).raw == b"N" * max(NAME_BUCKETS)


@pytest.mark.parametrize("bucket", NAME_BUCKETS)
def test_every_bucket_decodes_to_its_exact_byte_count(bucket):
    model = RoomNameIn(name_blob=b64_of(bucket, b"K"))

    assert model.raw == b"K" * bucket


@pytest.mark.parametrize("bucket", NAME_BUCKETS)
@pytest.mark.parametrize("delta", [-1, 1])
def test_a_blob_one_byte_off_a_bucket_is_a_bad_bucket(bucket, delta):
    """The boundary the exact-length half owns, on both sides of both buckets."""
    with pytest.raises(BadBucket):
        RoomNameIn(name_blob=b64_of(bucket + delta))


def test_a_blob_between_the_two_buckets_is_a_bad_bucket():
    with pytest.raises(BadBucket):
        RoomNameIn(name_blob=b64_of(640))


def test_a_string_at_the_character_bound_is_refused_by_the_decoder_not_by_length():
    """The boundary of the length guard from below: `MAX_NAME_CHARS` characters
    pass it, so whatever refuses them is the exact-length rule."""
    at_the_bound = "A" * MAX_NAME_CHARS

    with pytest.raises(BadBucket):
        RoomNameIn(name_blob=at_the_bound)


def test_a_string_one_character_past_the_bound_never_reaches_the_decoder():
    """And from above: one character more is a length failure, which is what keeps
    a megabyte of base64 from being decoded before it is refused."""
    with pytest.raises(ValidationError) as exc_info:
        RoomNameIn(name_blob="A" * (MAX_NAME_CHARS + 1))

    assert error_types(exc_info) == {"string_too_long"}


def test_an_empty_name_is_a_length_failure_rather_than_a_bad_bucket():
    """`min_length=1` runs first, so the empty string is `invalid_request`. The
    distinction is what the client branches on."""
    with pytest.raises(ValidationError) as exc_info:
        RoomNameIn(name_blob="")

    assert error_types(exc_info) == {"string_too_short"}


@pytest.mark.parametrize(
    "blob",
    [
        "@@@not-base64@@@",
        "QUFB QUFB",
        "QUFB\nQUFB",
        "QUFB\x00QUFB",
        "QUFB\x07QUFB",
        "QUFB\x1bQUFB",
        "====",
    ],
)
def test_a_string_outside_the_base64_alphabet_is_a_bad_bucket(blob):
    """Control characters included: `validate=True` refuses them rather than
    skipping them, so a NUL never reaches the column."""
    with pytest.raises(BadBucket):
        RoomNameIn(name_blob=blob)


@pytest.mark.parametrize("value", [5, 1.5, True, None, [], {}, b"bytes"])
def test_a_name_that_is_not_a_string_is_refused_rather_than_converted(value):
    """Strict mode: an integer is not coerced into a string on the way in."""
    with pytest.raises(ValidationError) as exc_info:
        RoomNameIn(name_blob=value)

    assert error_fields(exc_info) == {"name_blob"}


def test_a_missing_name_is_an_invalid_request_and_never_a_bad_bucket():
    """The reason the decode is an after-validator: `BadBucket` carries its own
    code and never names a field, so a body missing the field entirely has to
    fail as a field error first."""
    with pytest.raises(ValidationError) as exc_info:
        RoomNameIn()

    assert error_types(exc_info) == {"missing"}


def test_an_undeclared_field_is_refused_rather_than_ignored():
    with pytest.raises(ValidationError) as exc_info:
        RoomNameIn(name_blob=b64_of(min(NAME_BUCKETS)), owner="alice")

    assert error_types(exc_info) == {"extra_forbidden"}
    assert error_fields(exc_info) == {"owner"}


def test_the_raw_property_is_read_only_so_a_route_cannot_swap_the_decoded_bytes():
    """The route hands `payload.raw` straight to the column, so the decoded bytes
    must be the ones this model decoded."""
    model = RoomNameIn(name_blob=b64_of(min(NAME_BUCKETS), b"R"))

    with pytest.raises(AttributeError):
        model.raw = b"x" * min(NAME_BUCKETS)


# The accepting half of the property, pinned so it is exercised rather than left
# to the strategy to stumble on.
@example(size=min(NAME_BUCKETS))
@example(size=max(NAME_BUCKETS))
@given(size=st.integers(min_value=1, max_value=LARGEST_DECODABLE))
def test_exactly_the_bucket_lengths_decode_and_every_other_length_is_refused(size):
    """The whole of the length guard as one property, over every byte count the
    character bound admits."""
    blob = b64_of(size)

    if size in set(NAME_BUCKETS):
        assert RoomNameIn(name_blob=blob).raw == b"N" * size
    else:
        with pytest.raises(BadBucket):
            RoomNameIn(name_blob=blob)


@given(text=st.text(alphabet="AB=+/ \n\x00\x01é", min_size=1, max_size=32))
def test_every_short_string_is_refused_by_one_of_the_two_guards_and_no_other(text):
    """Thirty-two base64 characters decode to at most twenty-four bytes, so no
    string this short is a bucket length and every one of them has to be refused.
    What matters is which refusal: only these two have a rendered code, and
    anything else reaches the generic handler as a `500`."""
    with pytest.raises((BadBucket, ValidationError)):
        RoomNameIn(name_blob=text)


def test_the_read_model_says_four_facts_about_a_room_and_no_more():
    """A field added here is a new thing the server tells a client about a room —
    which for this design would have to be state it does not hold."""
    assert set(RoomOut.model_fields) == {
        "room_id",
        "name_blob",
        "updated_date",
        "live_count",
    }


def test_the_create_model_answers_the_capability_and_nothing_else():
    assert set(RoomCreatedOut.model_fields) == {"room_id"}


def test_the_token_model_answers_the_three_facts_a_client_needs_to_connect():
    assert set(RoomTokenOut.model_fields) == {"url", "token", "expires_in"}
