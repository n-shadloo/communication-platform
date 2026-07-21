import uuid

from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenRefreshSerializer

from devices.models import Device

from .models import username_validator

# A revoked device, a wrong generation, and a deactivated account are all reported
# identically: the client learns only that this token is finished (§A8).
TOKEN_REVOKED = {"code": "token_revoked", "detail": "Token is no longer valid."}


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
    username = serializers.CharField(max_length=32)
    # Bounded so an oversized body cannot turn Argon2id into a CPU sink.
    password = serializers.CharField(max_length=128, trim_whitespace=False)

    def validate_username(self, value):
        value = value.lower()
        username_validator(value)
        return value

    def validate_password(self, value):
        validate_password(value)
        return value


class LoginSerializer(StrictSerializer):
    username = serializers.CharField(max_length=32)
    password = serializers.CharField(max_length=128, trim_whitespace=False)
    device_id = serializers.UUIDField(required=False)


class LogoutSerializer(StrictSerializer):
    refresh = serializers.CharField(max_length=4096, trim_whitespace=False)


class ProfileBlobSerializer(StrictSerializer):
    # Base64 of the largest PROFILE_BUCKETS entry plus padding headroom; the exact
    # length check is decode_blob_or_400's job.
    blob = serializers.CharField(max_length=8192, trim_whitespace=False)
    version = serializers.IntegerField(min_value=0)


class DeviceTokenRefreshSerializer(TokenRefreshSerializer):
    """Standard rotation plus the §A8 device checks, so revoking a device kills its
    refresh token immediately rather than at the end of the access-token window."""

    def validate(self, attrs):
        try:
            token = self.token_class(attrs["refresh"])
        except TokenError as exc:
            raise InvalidToken(exc.args[0])

        if token.get("scope") != "full":
            raise AuthenticationFailed(TOKEN_REVOKED)

        device_id = token.get("device_id")
        try:
            uuid.UUID(str(device_id))
        except (AttributeError, TypeError, ValueError):
            raise AuthenticationFailed(TOKEN_REVOKED)

        device = (Device.objects
                  .select_related("user")
                  .filter(id=device_id, revoked_date__isnull=True)
                  .first())
        if (device is None
                or str(device.user_id) != str(token.get("user_id"))
                or token.get("tgen") != device.token_generation
                or not device.user.is_active):
            raise AuthenticationFailed(TOKEN_REVOKED)

        return super().validate(attrs)
