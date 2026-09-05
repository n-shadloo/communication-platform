import base64

from django.test import SimpleTestCase
from hypothesis import given
from hypothesis import strategies as st

from core.buckets import (
    DEVICELOG_BUCKETS,
    ENVELOPE_BUCKETS,
    LABEL_BUCKETS,
    SIGNAL_BUCKETS,
    in_bucket,
)
from core.fields import BadBucket, decode_blob_or_400

BUCKET_SETS = (ENVELOPE_BUCKETS, LABEL_BUCKETS, DEVICELOG_BUCKETS, SIGNAL_BUCKETS)


def b64(nbytes):
    return base64.b64encode(b"\x00" * nbytes).decode()


class DecodeBlobOrBadBucketTests(SimpleTestCase):
    """Exactly one property is enforced on every blob: its length is in the bucket
    set."""

    def test_exact_bucket_lengths_are_accepted(self):
        for bucket_set in BUCKET_SETS:
            for size in bucket_set:
                with self.subTest(bucket_set=bucket_set, size=size):
                    self.assertEqual(len(decode_blob_or_400(b64(size), bucket_set)), size)

    def test_off_by_one_lengths_are_rejected(self):
        for bucket_set in BUCKET_SETS:
            for size in bucket_set:
                for wrong in (size - 1, size + 1):
                    with self.subTest(bucket_set=bucket_set, size=wrong):
                        with self.assertRaises(BadBucket):
                            decode_blob_or_400(b64(wrong), bucket_set)

    def test_lengths_outside_every_bucket_are_rejected(self):
        for bucket_set in BUCKET_SETS:
            for wrong in (0, 1, max(bucket_set) * 2):
                with self.subTest(bucket_set=bucket_set, size=wrong):
                    with self.assertRaises(BadBucket):
                        decode_blob_or_400(b64(wrong), bucket_set)

    def test_non_base64_input_is_rejected(self):
        for junk in ("not base64!!", "@@@@", "AAA", "AA=A", "  ", None, 12345, b"\x00"):
            with self.subTest(junk=junk):
                with self.assertRaises(BadBucket):
                    decode_blob_or_400(junk, ENVELOPE_BUCKETS)

    def test_rejection_never_echoes_the_payload(self):
        secret = b64(ENVELOPE_BUCKETS[0] + 1)
        with self.assertRaises(BadBucket) as caught:
            decode_blob_or_400(secret, ENVELOPE_BUCKETS)

        self.assertNotIn(secret, str(caught.exception))
        self.assertEqual(caught.exception.args, ())


class BucketSetShapeTests(SimpleTestCase):
    """What every published set has to be, whatever sizes it holds.

    `core/API.md` publishes these tables and a client pads to them, so the shape
    is contract: `core/tests/test_endpoint_references.py` compares the table to
    these lists element by element, which only means anything while the lists are
    ordered and free of duplicates.
    """

    def sets(self):
        from core import buckets

        return {
            name: value
            for name, value in vars(buckets).items()
            if name.endswith("_BUCKETS") and isinstance(value, list)
        }

    def test_every_published_set_is_ascending_and_free_of_duplicates(self):
        for name, sizes in self.sets().items():
            with self.subTest(name=name):
                self.assertEqual(sizes, sorted(set(sizes)))

    def test_every_size_is_a_positive_number_of_bytes(self):
        """A zero-length bucket would accept the empty payload, which carries the
        one fact padding exists to hide: that there was nothing to send."""
        for name, sizes in self.sets().items():
            with self.subTest(name=name):
                self.assertTrue(all(size > 0 for size in sizes), sizes)

    def test_the_guard_actually_found_the_published_sets(self):
        self.assertEqual(len(self.sets()), 7)

    def test_this_deployment_serves_the_default_envelope_set(self):
        """`ENVELOPE_BUCKETS_OVERRIDE` exists for a deployment that measured its
        own traffic. This one has not, so the sizes in `core/API.md` and the sizes
        a client pads to are the defaults."""
        from django.conf import settings

        self.assertIsNone(getattr(settings, "ENVELOPE_BUCKETS_OVERRIDE", None))
        self.assertEqual(ENVELOPE_BUCKETS, [1024, 4096, 16384, 65536, 262144])

    def test_a_post_quantum_initial_message_lands_in_the_four_kilobyte_bucket(self):
        """The recorded reason there is no 2048 step: an ML-KEM-768 ciphertext is
        1088 bytes, so a PQXDH initial message is already over the 1024 bucket and
        a 2048 one would only split the traffic that pads to 4096."""
        pqxdh_ciphertext = 1088

        self.assertNotIn(2048, ENVELOPE_BUCKETS)
        self.assertEqual(
            min(size for size in ENVELOPE_BUCKETS if size >= pqxdh_ciphertext), 4096
        )


class InBucketTests(SimpleTestCase):
    """`in_bucket` is the predicate `decode_blob_or_400` enforces, exposed for the
    services that check a length they did not decode themselves."""

    @given(
        nbytes=st.integers(min_value=-4096, max_value=1 << 20),
        bucket_set=st.sampled_from(BUCKET_SETS),
    )
    def test_membership_is_exact_for_any_length_and_any_published_set(
        self, nbytes, bucket_set
    ):
        """Exact, not "at most": a payload shorter than a bucket is a payload
        whose true length leaked."""
        self.assertEqual(in_bucket(nbytes, bucket_set), nbytes in set(bucket_set))

    @given(payload=st.binary(max_size=64))
    def test_the_decoder_accepts_exactly_what_the_predicate_admits(self, payload):
        """One rule, two call sites. A service that checked a length with
        `in_bucket` and a route that decoded it with `decode_blob_or_400` must
        never disagree about the same bytes."""
        small = [4, 16, 64]
        encoded = base64.b64encode(payload).decode()
        admitted = in_bucket(len(payload), small)

        try:
            decode_blob_or_400(encoded, small)
        except BadBucket:
            self.assertFalse(admitted)
        else:
            self.assertTrue(admitted)

    def test_the_set_may_arrive_as_any_iterable_of_lengths(self):
        """Callers hand it a list, a tuple or a set; the answer is the same."""
        for shape in ([256], (256,), {256}, frozenset({256})):
            with self.subTest(shape=shape):
                self.assertTrue(in_bucket(256, shape))
                self.assertFalse(in_bucket(255, shape))

    def test_an_empty_set_admits_nothing(self):
        self.assertFalse(in_bucket(0, []))
        self.assertFalse(in_bucket(1024, []))
