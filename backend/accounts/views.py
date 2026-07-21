import base64
import secrets
from functools import lru_cache

from django.contrib.auth.hashers import check_password, make_password
from django.db import IntegrityError, transaction
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from core.buckets import PROFILE_BUCKETS
from core.fields import decode_blob_or_400
from devices.models import Device

from .models import ProfileBlob, User
from .serializers import (
    DeviceTokenRefreshSerializer,
    LoginSerializer,
    LogoutSerializer,
    ProfileBlobSerializer,
    RegisterSerializer,
)
from .tokens import issue_full, issue_register_scope


def error(code, detail, status):
    return Response({"code": code, "detail": detail}, status=status)


def invalid_request(errors):
    # Field names and validator messages only; submitted values are never echoed.
    return error("invalid_request", errors, 400)


class IsFullScope(BasePermission):
    """A register-scope token's only power is POST /me/devices (§A8)."""

    message = {"code": "scope_forbidden",
               "detail": "This token cannot access this endpoint."}

    def has_permission(self, request, view):
        return bool(request.auth is not None and request.auth.get("scope") == "full")


@lru_cache(maxsize=1)
def dummy_password_hash():
    """Argon2id hash of a throwaway secret. Verifying against it costs the same as a
    real check, so login timing does not reveal whether a username exists (§A5)."""
    return make_password(secrets.token_urlsafe(32))


class RegisterView(APIView):
    authentication_classes = []
    permission_classes = []
    throttle_scope = "register"

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        try:
            with transaction.atomic():
                user = User.objects.create_user(
                    username=serializer.validated_data["username"],
                    password=serializer.validated_data["password"],
                )
        except IntegrityError:
            return error("username_taken", "That username is taken.", 400)
        # The account stays inactive until the owner activates it in the admin (§7).
        return Response({"user_id": str(user.id)}, status=201)


class LoginView(APIView):
    authentication_classes = []
    permission_classes = []
    throttle_scope = "login"

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        username = serializer.validated_data["username"].lower()
        password = serializer.validated_data["password"]
        device_id = serializer.validated_data.get("device_id")

        user = User.objects.filter(username=username).first()
        if user is None:
            # Spend the same Argon2id work a real verify would.
            check_password(password, dummy_password_hash())
            return self.invalid_credentials()
        if not user.check_password(password):
            return self.invalid_credentials()
        # Only after the password is proven does activation state become observable.
        if not user.is_active:
            return error("account_inactive", "This account is not activated yet.", 403)

        device = None
        if device_id is not None:
            device = Device.objects.filter(
                id=device_id, user_id=user.id, revoked_date__isnull=True,
            ).first()
        if device is None:
            # No usable device: a short-lived token whose only power is adding one.
            return Response({"access": issue_register_scope(user),
                             "user_id": str(user.id),
                             "scope": "register"})

        access, refresh = issue_full(user, device)
        return Response({"access": access,
                         "refresh": refresh,
                         "user_id": str(user.id),
                         "device_id": str(device.id),
                         "scope": "full"})

    @staticmethod
    def invalid_credentials():
        return error("invalid_credentials", "Invalid username or password.", 401)


class DeviceTokenRefreshView(TokenRefreshView):
    authentication_classes = []
    permission_classes = []
    serializer_class = DeviceTokenRefreshSerializer


class LogoutView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]

    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            # Never let one account blacklist another's token.
            if str(token.get("user_id")) == str(request.user.id):
                token.blacklist()
        except TokenError:
            pass  # already expired or blacklisted; logout is idempotent
        return Response(status=205)


class UserDirectoryView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]

    def get(self, request):
        users = (User.objects
                 .filter(is_active=True)
                 .order_by("username")
                 .values_list("id", "username"))
        return Response({"users": [{"user_id": str(user_id), "username": username}
                                   for user_id, username in users]})


class UserProfileView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]

    def get(self, request, user_id):
        row = (ProfileBlob.objects
               .filter(user_id=user_id, user__is_active=True)
               .values_list("blob", "version")
               .first())
        if row is None:
            return error("not_found", "No profile for that user.", 404)
        blob, version = row
        return Response({"blob": base64.b64encode(bytes(blob)).decode(),
                         "version": version})


class MyProfileView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]

    def put(self, request):
        serializer = ProfileBlobSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        blob = decode_blob_or_400(serializer.validated_data["blob"], PROFILE_BUCKETS)
        version = serializer.validated_data["version"]
        try:
            with transaction.atomic():
                profile = (ProfileBlob.objects
                           .select_for_update()
                           .filter(user_id=request.user.id)
                           .first())
                if profile is None:
                    ProfileBlob.objects.create(user_id=request.user.id, blob=blob,
                                               version=version)
                elif version <= profile.version:
                    return error("stale_version", "Version must increase.", 409)
                else:
                    profile.blob = blob
                    profile.version = version
                    profile.save(update_fields=["blob", "version", "updated_date"])
        except IntegrityError:
            return error("stale_version", "Version must increase.", 409)
        return Response({"version": version})
