import base64

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework.exceptions import APIException

from core.buckets import PROFILE_BUCKETS
from core.fields import decode_blob_or_400

from .models import User, username_validator


class UsernameTaken(APIException):
    """§A5 reports a duplicate inline as `400 {"code":"username_taken"}`. Raised both
    from validation and from the view's IntegrityError guard, so the concurrent-
    registration race lands on the same contract instead of a 500."""

    status_code = 400

    def __init__(self):
        super().__init__({"code": "username_taken", "detail": "That username is taken."})


class StrictSerializer(serializers.Serializer):
    """Unknown fields are rejected rather than silently ignored (§A5)."""

    def to_internal_value(self, data):
        if isinstance(data, dict):
            unknown = sorted(set(data) - set(self.fields))
            if unknown:
                raise serializers.ValidationError(
                    {name: "Unexpected field." for name in unknown}
                )
        return super().to_internal_value(data)


class RegisterSerializer(StrictSerializer):
    # The `^[a-z0-9_]{3,32}$` rule is applied through the model validator in
    # validate_username, i.e. *after* lowercasing. As a RegexField it would reject
    # "BoB" before the normalisation the User manager and model both perform.
    username = serializers.CharField(max_length=32)
    password = serializers.CharField(write_only=True, max_length=256,
                                     trim_whitespace=False)

    def validate_username(self, value):
        value = value.lower()
        username_validator(value)
        if User.objects.filter(username=value).exists():
            raise UsernameTaken()
        return value

    def validate_password(self, value):
        try:
            validate_password(value)
        except DjangoValidationError as e:
            raise serializers.ValidationError(list(e.messages))
        return value

    def create(self, data):
        # Account is created INACTIVE; the owner activates it (structure §7).
        return User.objects.create_user(username=data["username"],
                                        password=data["password"])


class LoginSerializer(StrictSerializer):
    """Login parses through a serializer, not `request.data.get(...)`: a non-string
    username (`.lower()` on a dict) and a non-UUID device_id (straight into a UUID
    column filter) are both unauthenticated 500s otherwise."""

    username = serializers.CharField(max_length=32)
    password = serializers.CharField(max_length=256, trim_whitespace=False)
    device_id = serializers.UUIDField(required=False)


class RefreshTokenSerializer(StrictSerializer):
    """Bounds the token string and keeps a non-string `refresh` out of the JWT
    decoder, which raises past `except TokenError` into a 500."""

    refresh = serializers.CharField(max_length=4096, trim_whitespace=False)


class DirectoryUserSerializer(serializers.Serializer):
    user_id = serializers.UUIDField(source="id")
    username = serializers.CharField()


class ProfileReadSerializer(serializers.Serializer):
    blob = serializers.SerializerMethodField()
    version = serializers.IntegerField()

    def get_blob(self, obj):
        return base64.b64encode(bytes(obj.blob)).decode()


class ProfileWriteSerializer(StrictSerializer):
    # Base64 of the largest PROFILE_BUCKETS entry plus headroom; the exact length
    # check is decode_blob_or_400's job.
    blob = serializers.CharField(max_length=8192, trim_whitespace=False)
    version = serializers.IntegerField(min_value=0)

    def validate(self, data):
        data["raw"] = decode_blob_or_400(data["blob"], PROFILE_BUCKETS)
        return data
