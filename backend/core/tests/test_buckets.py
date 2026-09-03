import base64

from django.test import SimpleTestCase

from core.buckets import DEVICELOG_BUCKETS, ENVELOPE_BUCKETS, NAME_BUCKETS
from core.fields import BadBucket, decode_blob_or_400

BUCKET_SETS = (ENVELOPE_BUCKETS, NAME_BUCKETS, DEVICELOG_BUCKETS)


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
