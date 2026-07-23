from rest_framework.permissions import BasePermission


class IsFullScope(BasePermission):
    """DeviceJWTAuthentication authenticates register-scope tokens (it sets
    `auth_device = None` and returns the user), so `IsAuthenticated` alone is
    satisfied by one. Set as a project-wide default so a new endpoint stays closed
    until someone deliberately opens it; `POST /me/devices` is the one view that
    opts down."""

    message = {"code": "scope_forbidden",
               "detail": "This token cannot access this endpoint."}

    def has_permission(self, request, view):
        return bool(request.auth is not None and request.auth.get("scope") == "full")
