from rest_framework import serializers

from accounts.serializers import StrictSerializer
from core.buckets import NAME_BUCKETS
from core.fields import decode_blob_or_400

# Base64 of the largest bucket plus padding headroom (messaging's pattern): bounds what
# reaches b64decode; the exact length check is decode_blob_or_400's job.
MAX_NAME_CHARS = 4 * ((max(NAME_BUCKETS) + 2) // 3) + 8


class RoomNameSerializer(StrictSerializer):
    name_blob = serializers.CharField(max_length=MAX_NAME_CHARS, trim_whitespace=False)

    def validate(self, d):
        d["raw"] = decode_blob_or_400(d["name_blob"], NAME_BUCKETS); return d
