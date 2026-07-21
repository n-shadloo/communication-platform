from rest_framework.permissions import BasePermission


class IsFullScope(BasePermission):
    """A register-scope token's only power is `POST /me/devices` (ARCHITECTURE §A8).

    DeviceJWTAuthentication *authenticates* register-scope tokens (it sets
    `auth_device = None` and returns the user), so `IsAuthenticated` on its own is
    satisfied by one. This is a project-wide default so an endpoint added in a later
    phase is closed until someone deliberately opens it — `POST /me/devices` is the
    one view expected to opt down.
    """

    message = {"code": "scope_forbidden",
               "detail": "This token cannot access this endpoint."}

    def has_permission(self, request, view):
        return bool(request.auth is not None and request.auth.get("scope") == "full")
