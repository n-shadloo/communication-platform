from rest_framework import serializers


class StrictSerializer(serializers.Serializer):
    """Rejects unknown fields rather than silently ignoring them."""

    def to_internal_value(self, data):
        if isinstance(data, dict):
            unknown = sorted(set(data) - set(self.fields))
            if unknown:
                raise serializers.ValidationError(
                    {name: "Unexpected field." for name in unknown}
                )
        return super().to_internal_value(data)
