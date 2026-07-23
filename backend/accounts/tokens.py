from datetime import timedelta

from django.conf import settings
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

def issue_full(user, device):
    refresh = RefreshToken.for_user(user)
    refresh["device_id"] = str(device.id)
    refresh["tgen"] = device.token_generation
    refresh["scope"] = "full"
    access = refresh.access_token
    access["device_id"] = str(device.id)
    access["tgen"] = device.token_generation
    access["scope"] = "full"
    return str(access), str(refresh)

def issue_register_scope(user):
    access = AccessToken.for_user(user)
    access.set_exp(lifetime=timedelta(minutes=settings.REGISTER_SCOPE_ACCESS_MIN))
    access["scope"] = "register"
    return str(access)
