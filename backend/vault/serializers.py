from rest_framework import serializers

from accounts.serializers import StrictSerializer
from core.buckets import BACKUP_BUCKETS
from core.fields import decode_blob_or_400

# Base64 of the largest bucket plus padding headroom: bounds what reaches b64decode;
# the exact length check is decode_blob_or_400's job.
MAX_BACKUP_CHARS = 4 * ((max(BACKUP_BUCKETS) + 2) // 3) + 8


class KeyBackupSerializer(StrictSerializer):
    blob = serializers.CharField(max_length=MAX_BACKUP_CHARS, trim_whitespace=False)
    version = serializers.IntegerField(min_value=0)

    def validate(self, data):
        data["raw"] = decode_blob_or_400(data["blob"], BACKUP_BUCKETS)
        return data
