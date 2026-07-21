from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken
from rest_framework.exceptions import AuthenticationFailed
from devices.models import Device

class DeviceJWTAuthentication(JWTAuthentication):
    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        if not user.is_active:
            raise AuthenticationFailed({"code": "account_inactive"}, code=403)
        return user

    def authenticate(self, request):
        result = super().authenticate(request)
        if result is None:
            return None
        user, token = result
        scope = token.get("scope")
        device_id = token.get("device_id")
        if scope == "full":
            try:
                device = Device.objects.only(
                    "id", "user_id", "token_generation", "revoked_date"
                ).get(id=device_id, user_id=user.id)
            except Device.DoesNotExist:
                raise AuthenticationFailed({"code": "token_revoked"})
            if device.revoked_date is not None or token.get("tgen") != device.token_generation:
                raise AuthenticationFailed({"code": "token_revoked"})
            request.auth_device = device
        elif scope == "register":
            request.auth_device = None
        else:
            raise InvalidToken("unknown scope")
        return user, token
