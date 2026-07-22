from rest_framework import serializers

from core.buckets import NAME_BUCKETS
from core.fields import decode_blob_or_400


class RoomNameSerializer(serializers.Serializer):
    name_blob = serializers.CharField()

    def validate(self, d):
        d["raw"] = decode_blob_or_400(d["name_blob"], NAME_BUCKETS); return d
