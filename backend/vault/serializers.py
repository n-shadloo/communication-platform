from rest_framework import serializers
from core.fields import decode_blob_or_400
from core.buckets import BACKUP_BUCKETS, ENVELOPE_BUCKETS

class KeyBackupSerializer(serializers.Serializer):
    blob = serializers.CharField()
    version = serializers.IntegerField(min_value=0)
    def validate(self, d):
        d["raw"] = decode_blob_or_400(d["blob"], BACKUP_BUCKETS); return d

class HistoryAppendSerializer(serializers.Serializer):
    class _Rec(serializers.Serializer):
        blob = serializers.CharField()
        def validate(self, d):
            d["raw"] = decode_blob_or_400(d["blob"], ENVELOPE_BUCKETS); return d
    records = serializers.ListField(child=_Rec(), min_length=1, max_length=100)
