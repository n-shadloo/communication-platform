from rest_framework import serializers

from accounts.serializers import StrictSerializer
from core.buckets import ENVELOPE_BUCKETS
from core.fields import decode_blob_or_400

# Base64 length cap for the largest bucket plus padding headroom; the exact size check
# is decode_blob_or_400's job. Without the cap a client could push an arbitrarily long
# string into b64decode. Computed because ENVELOPE_BUCKETS is settings-tunable.
MAX_BLOB_CHARS = 4 * ((max(ENVELOPE_BUCKETS) + 2) // 3) + 8


class OutgoingItemSerializer(StrictSerializer):
    device_id = serializers.UUIDField()
    blob = serializers.CharField(max_length=MAX_BLOB_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["raw"] = decode_blob_or_400(data["blob"], ENVELOPE_BUCKETS)
        return data


class SendSerializer(StrictSerializer):
    messages = serializers.ListField(
        child=OutgoingItemSerializer(), min_length=1, max_length=256
    )
