"""The REST Framework adapter over the one token verifier.

The apps that have not moved to FastAPI still authenticate through REST
Framework. This class holds no verification of its own: it calls `api.auth`, so a
token one stack revokes is dead on the other, and it keeps the
`request.auth_device` contract the remaining views read.
"""

from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed

from accounts.models import User
from api.auth import FULL, decode_access, load_device
from api.errors import TOKEN_REVOKED, UNAUTHENTICATED, ApiError


class DeviceJWTAuthentication(BaseAuthentication):
    def authenticate_header(self, request):
        # Returning a challenge is what makes a missing token a 401 rather than a
        # 403, which is the status the FastAPI surface answers for it too.
        return "Bearer"

    def authenticate(self, request):
        header = request.META.get("HTTP_AUTHORIZATION", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer":
            return None
        try:
            return self._principal(request, token.strip())
        except ApiError as exc:
            raise AuthenticationFailed({"code": exc.code, "detail": exc.detail})

    @staticmethod
    def _principal(request, token):
        if not token:
            raise ApiError(401, "unauthenticated", UNAUTHENTICATED)
        claims = decode_access(token)
        if claims["scope"] == FULL:
            device = load_device(claims)
            if device is None:
                raise ApiError(401, "token_revoked", TOKEN_REVOKED)
            request.auth_device = device
            return device.user, claims
        # A register-scope token names no device; its only power is adding one.
        user = (
            User.objects.filter(id=claims["user_id"], is_active=True).only("id").first()
        )
        if user is None:
            raise ApiError(401, "token_revoked", TOKEN_REVOKED)
        request.auth_device = None
        return user, claims
