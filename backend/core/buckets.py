from django.conf import settings

# A PQXDH initial message carrying an ML-KEM-768 ciphertext (1088 bytes) lands in
# the 4096 bucket, not 1024. A 2048 bucket is deliberately not added to reduce the
# waste: fewer buckets means better length uniformity across all traffic, and at
# this deployment's scale (tens of users) the wasted bytes are irrelevant.
ENVELOPE_BUCKETS = getattr(settings, "ENVELOPE_BUCKETS_OVERRIDE", None) or [
    1024,
    4096,
    16384,
    65536,
    262144,
]
PROFILE_BUCKETS = [1024, 4096]
LABEL_BUCKETS = [256, 1024]
DEVICELOG_BUCKETS = [256, 1024]
BACKUP_BUCKETS = [4096, 16384, 65536, 262144, 1048576]
ATTACHMENT_BUCKETS = [65536, 262144, 1048576, 4194304, 16777216, 67108864]


def in_bucket(nbytes, bucket_set):
    return nbytes in set(bucket_set)
