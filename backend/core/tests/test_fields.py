"""The opaque blob column, and the decoder every route puts in front of it.

`decode_blob_or_400` is the one function that turns client text into stored bytes.
It stands on the boundary between an attacker-controlled string and a `bytea`, so
the property that matters is totality: for *any* input it either returns bytes of
an exact bucket length or raises `BadBucket`. A `binascii.Error`, a
`UnicodeDecodeError` or a `TypeError` escaping it is a `500` on a malformed
payload — an unhandled failure where the contract publishes `400 bad_bucket` —
and the exception must carry no part of the payload, because an error body of this
API never echoes input.

`core/tests/test_buckets.py` holds the table-driven cases over the real bucket sets
and the `in_bucket` properties; this file holds the decoder's own properties and
the field the decoded bytes land in.
"""

import base64

import pytest
from django.test import SimpleTestCase
from hypothesis import example, given
from hypothesis import strategies as st

from core.buckets import ENVELOPE_BUCKETS, LABEL_BUCKETS
from core.fields import BadBucket, OpaqueBlobField, decode_blob_or_400

# A bucket set of the same shape as the real ones — a few exact lengths, nothing
# between them — small enough that Hypothesis reaches both sides of every edge.
# The real sets start at 256 bytes, so a generator aimed at them would spend its
# whole budget on refusals and never once produce an accepted blob.
BUCKETS = [4, 16, 64]
BIGGEST = max(BUCKETS)


@given(payload=st.binary(max_size=BIGGEST + 8))
def test_bytes_round_trip_at_a_bucket_length_and_are_refused_anywhere_else(payload):
    """The whole contract in one property: length decides, and nothing else does.
    Every byte value, every length on and around each bucket."""
    encoded = base64.b64encode(payload).decode()

    if len(payload) in set(BUCKETS):
        assert decode_blob_or_400(encoded, BUCKETS) == payload
    else:
        with pytest.raises(BadBucket):
            decode_blob_or_400(encoded, BUCKETS)


@given(payload=st.binary(min_size=4, max_size=4))
def test_the_encoding_may_arrive_as_bytes_as_well_as_text(payload):
    """`base64.b64decode` takes either, and a client library that sends the
    encoded form as bytes must not be a different contract."""
    encoded = base64.b64encode(payload)

    assert decode_blob_or_400(encoded, BUCKETS) == payload
    assert decode_blob_or_400(encoded.decode(), BUCKETS) == payload


@given(text=st.text(max_size=200))
@example(text=base64.b64encode(b"\x00" * min(BUCKETS)).decode())
def test_arbitrary_text_is_either_a_bucket_length_blob_or_a_bad_bucket(text):
    """Totality over text: non-ASCII, control characters, whitespace, lone
    surrogate-free garbage. `b64decode` raises `UnicodeEncodeError` on a
    non-ASCII string and `binascii.Error` on a bad alphabet, and neither may
    escape as a `500`."""
    try:
        raw = decode_blob_or_400(text, BUCKETS)
    except BadBucket:
        return
    except Exception as exc:
        pytest.fail(f"{type(exc).__name__} escaped the decoder: {type(exc)}")

    assert isinstance(raw, bytes)
    assert len(raw) in set(BUCKETS)


@given(raw=st.binary(max_size=200))
@example(raw=base64.b64encode(b"\x00" * min(BUCKETS)))
def test_arbitrary_bytes_handed_in_as_the_encoding_never_escape_either(raw):
    """The same totality on the bytes branch, where the failure mode is a
    `binascii.Error` rather than a unicode one."""
    try:
        decoded = decode_blob_or_400(raw, BUCKETS)
    except BadBucket:
        return
    except Exception as exc:
        pytest.fail(f"{type(exc).__name__} escaped the decoder: {type(exc)}")

    assert len(decoded) in set(BUCKETS)


@given(
    value=st.one_of(
        st.none(),
        st.integers(),
        st.floats(allow_nan=True, allow_infinity=True),
        st.lists(st.integers(), max_size=4),
        st.dictionaries(st.text(max_size=4), st.integers(), max_size=2),
        st.booleans(),
    )
)
def test_a_value_that_is_not_text_at_all_is_a_bad_bucket(value):
    """A JSON body whose `blob` is a number, a list or `null` reaches the decoder
    as that object. `b64decode` answers a `TypeError`, which is a `500` unless it
    is caught here."""
    with pytest.raises(BadBucket):
        decode_blob_or_400(value, BUCKETS)


@given(text=st.text(min_size=len(repr(BadBucket())) + 1, max_size=120))
def test_a_refusal_never_carries_the_payload(text):
    """`400 bad_bucket` publishes `"Invalid payload."` and nothing else. An
    exception that stringified the input would put it in the traceback, and the
    traceback is what the scrub filter has to catch instead.

    Generated longer than `repr(BadBucket())` itself, so a payload "found" in the
    representation is a real echo rather than a coincidental substring of the
    class name — the first run of this property failed on the payload `)`.
    """
    try:
        decode_blob_or_400(text, BUCKETS)
    except BadBucket as exc:
        assert exc.args == ()
        assert str(exc) == ""
        assert text not in repr(exc)


class DecoderEdgeCases(SimpleTestCase):
    """The base64 shapes a permissive decoder accepts and this one must not.

    `validate=True` is what refuses them: without it `b64decode` discards every
    character outside the alphabet, so a padded, spaced or url-safe string decodes
    to *something* and the length check then passes or fails by accident.
    """

    def encoded(self, size=4):
        return base64.b64encode(b"\x00" * size).decode()

    def test_surrounding_whitespace_is_not_stripped(self):
        for spaced in (f" {self.encoded()}", f"{self.encoded()} ", f"{self.encoded()}\n"):
            with self.subTest(spaced=spaced):
                with self.assertRaises(BadBucket):
                    decode_blob_or_400(spaced, BUCKETS)

    def test_whitespace_inside_the_encoding_is_not_stripped(self):
        """A base64 body wrapped at 76 columns, which is what a MIME encoder
        produces and what a lenient decoder silently accepts."""
        blob = base64.b64encode(b"\x00" * 64).decode()
        wrapped = "\n".join([blob[:40], blob[40:]])

        with self.assertRaises(BadBucket):
            decode_blob_or_400(wrapped, BUCKETS)

    def test_the_url_safe_alphabet_is_not_the_standard_one(self):
        """`-` and `_` are a different encoding of the same bytes. Accepting both
        would mean one blob had two spellings on the wire."""
        payload = bytes(range(64))
        urlsafe = base64.urlsafe_b64encode(payload).decode()
        self.assertTrue({"-", "_"} & set(urlsafe), "pick a payload that differs")

        with self.assertRaises(BadBucket):
            decode_blob_or_400(urlsafe, BUCKETS)

    def test_missing_and_excess_padding_are_both_refused(self):
        blob = base64.b64encode(b"\x00" * 4).decode()  # "AAAAAA==" style

        for broken in (blob.rstrip("="), blob + "=", blob + "==", "A", "AA", "AAA"):
            with self.subTest(broken=broken):
                with self.assertRaises(BadBucket):
                    decode_blob_or_400(broken, BUCKETS)

    def test_the_empty_string_is_refused_rather_than_decoded_to_nothing(self):
        """It is valid base64 for zero bytes, and zero is in no bucket set."""
        with self.assertRaises(BadBucket):
            decode_blob_or_400("", BUCKETS)

    def test_an_empty_bucket_set_accepts_nothing(self):
        """The degenerate set. A field that lost its buckets must refuse every
        payload rather than accept every one — `test_manifest.py` is what stops
        such a field being declared at all."""
        with self.assertRaises(BadBucket):
            decode_blob_or_400(self.encoded(), [])

    def test_a_real_bucket_set_still_decides_by_exact_length(self):
        """Anchors the small set above to the sizes the deployment actually uses."""
        smallest = min(LABEL_BUCKETS)
        blob = base64.b64encode(b"\xa5" * smallest).decode()

        self.assertEqual(len(decode_blob_or_400(blob, LABEL_BUCKETS)), smallest)
        with self.assertRaises(BadBucket):
            decode_blob_or_400(blob, ENVELOPE_BUCKETS)


class OpaqueBlobFieldTests(SimpleTestCase):
    """The column the decoded bytes land in: a `bytea` that carries its bucket set
    as metadata, so `test_manifest.py` and `test_seizure_guard.py` can read it."""

    def test_the_bucket_set_is_a_set_whatever_it_was_declared_as(self):
        field = OpaqueBlobField(bucket_set=[64, 16, 16])

        self.assertEqual(field.bucket_set, {16, 64})

    def test_a_field_declared_without_buckets_holds_an_empty_set(self):
        """Not a crash and not a wildcard: the empty set is what the manifest
        guard reports as an unbucketed blob."""
        self.assertEqual(OpaqueBlobField().bucket_set, set())

    def test_the_column_is_never_editable_in_a_form(self):
        """Opaque ciphertext has no form widget, and the panel must never offer
        one — `accounts/tests/test_admin.py` proves the pages, this proves the
        default they inherit."""
        self.assertFalse(OpaqueBlobField(bucket_set=[16]).editable)

    def test_deconstruction_carries_the_buckets_in_a_stable_order(self):
        """A migration file is written from this. A set has no order, so an
        unsorted value would rewrite the migration on every `makemigrations`."""
        _name, path, args, kwargs = OpaqueBlobField(bucket_set={64, 4, 16}).deconstruct()

        self.assertEqual(path, "core.fields.OpaqueBlobField")
        self.assertEqual(kwargs["bucket_set"], [4, 16, 64])
        self.assertEqual(OpaqueBlobField(*args, **kwargs).bucket_set, {4, 16, 64})
