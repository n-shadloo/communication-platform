import uuid

from django.contrib.auth.hashers import check_password, make_password
from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from devices.models import Device

from .models import ProfileBlob, User
from .permissions import IsFullScope
from .serializers import (
    DirectoryUserSerializer,
    LoginSerializer,
    ProfileReadSerializer,
    ProfileWriteSerializer,
    RefreshTokenSerializer,
    RegisterSerializer,
    UsernameTaken,
)
from .tokens import issue_full, issue_register_scope

# A revoked device, a wrong generation, and a deactivated account are all reported
# identically: the client learns only that this token is finished.
TOKEN_REVOKED = {"code": "token_revoked", "detail": "Token is no longer valid."}

# A fixed invalid hash so an unknown-username login still spends Argon2 time.
_DUMMY_HASH = make_password("timing-equalizer-not-a-real-password")


def error(code, detail, status_code):
    return Response({"code": code, "detail": detail}, status=status_code)


def invalid_request(errors):
    # Field names and validator messages only; submitted values are never echoed.
    return error("invalid_request", errors, 400)


class RegisterView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_scope = "register"

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)

        try:
            with transaction.atomic():
                user = serializer.save()
        except IntegrityError:
            # The uniqueness probe in validate_username is advisory: two concurrent
            # registrations can both pass it and only the index settles it.
            raise UsernameTaken()
        return Response({"user_id": str(user.id)}, status=status.HTTP_201_CREATED)


class LoginView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_scope = "login"

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        username = serializer.validated_data["username"].lower()
        password = serializer.validated_data["password"]
        device_id = serializer.validated_data.get("device_id")

        user = (
            User.objects.filter(username=username)
            .only("id", "password", "is_active")
            .first()
        )
        if user is None:
            check_password(password, _DUMMY_HASH)  # equalize timing
            return self.invalid_credentials()
        # user.check_password (not the bare function) carries the setter that
        # transparently re-hashes when the configured Argon2 cost changes.
        if not user.check_password(password):
            return self.invalid_credentials()
        # Only once the password is proven does activation state become observable.
        if not user.is_active:
            return error("account_inactive", "This account is awaiting activation.", 403)

        if device_id:
            device = (
                Device.objects.filter(
                    id=device_id,
                    user_id=user.id,
                    revoked_date__isnull=True,
                )
                .only("id", "token_generation")
                .first()
            )
            if device is not None:
                access, refresh = issue_full(user, device)
                return Response(
                    {
                        "access": access,
                        "refresh": refresh,
                        "user_id": str(user.id),
                        "device_id": str(device.id),
                        "scope": "full",
                    }
                )

        # No or unknown device: a short register-scope token whose only power is
        # POST /me/devices.
        return Response(
            {
                "access": issue_register_scope(user),
                "user_id": str(user.id),
                "scope": "register",
            }
        )

    @staticmethod
    def invalid_credentials():
        return error("invalid_credentials", "Username or password is incorrect.", 401)


class RefreshView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_scope = "refresh"

    def post(self, request):
        serializer = RefreshTokenSerializer(data=request.data)
        if not serializer.is_valid():
            return error("invalid_token", "Refresh token is missing or malformed.", 401)
        try:
            token = RefreshToken(
                serializer.validated_data["refresh"]
            )  # signature/expiry/blacklist
        except TokenError:
            return error("invalid_token", "Refresh token is missing or malformed.", 401)

        # A register-scope token must never rotate its way up to a full-scope pair.
        if token.get("scope") != "full":
            return Response(TOKEN_REVOKED, status=401)
        device_id = token.get("device_id")
        try:
            uuid.UUID(str(device_id))
        except (TypeError, ValueError):
            return Response(TOKEN_REVOKED, status=401)

        device = (
            Device.objects.filter(id=device_id, revoked_date__isnull=True)
            .select_related("user")
            .only("id", "user_id", "token_generation", "user__is_active")
            .first()
        )
        if (
            device is None
            or str(device.user_id) != str(token.get("user_id"))
            or token.get("tgen") != device.token_generation
            or not device.user.is_active
        ):
            return Response(TOKEN_REVOKED, status=401)

        token.blacklist()  # rotation: retire the presented refresh
        access, refresh = issue_full(device.user, device)
        return Response({"access": access, "refresh": refresh})


class LogoutView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def post(self, request):
        serializer = RefreshTokenSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)

        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            # Never let one account blacklist another's token.
            if str(token.get("user_id")) == str(request.user.id):
                token.blacklist()
        except TokenError:
            pass  # already expired or blacklisted; logout is idempotent
        return Response(status=status.HTTP_205_RESET_CONTENT)


class UserDirectoryView(ListAPIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"
    serializer_class = DirectoryUserSerializer
    pagination_class = None

    def get_queryset(self):
        return (
            User.objects.filter(is_active=True)
            .only("id", "username")
            .order_by("username")
        )

    def list(self, request, *args, **kwargs):
        # The response contract wraps the list in {"users": [...]}; ListAPIView would
        # render a bare array.
        data = self.get_serializer(self.get_queryset(), many=True).data
        return Response({"users": data})


class ProfileDetailView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request, user_id):
        profile = (
            ProfileBlob.objects.filter(user_id=user_id, user__is_active=True)
            .only("blob", "version")
            .first()
        )
        if profile is None:
            return error("not_found", "No profile for that user.", 404)
        return Response(ProfileReadSerializer(profile).data)


class MyProfileView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request):
        profile = (
            ProfileBlob.objects.filter(user_id=request.user.id)
            .only("blob", "version")
            .first()
        )
        if profile is None:
            return error("not_found", "No profile yet.", 404)
        return Response(ProfileReadSerializer(profile).data)

    def put(self, request):
        serializer = ProfileWriteSerializer(data=request.data)
        if not serializer.is_valid():
            return invalid_request(serializer.errors)
        raw = serializer.validated_data["raw"]
        new_version = serializer.validated_data["version"]

        try:
            with transaction.atomic():
                # .only("version"): the locked read exists to compare versions, so the
                # stored blob is not dragged back with it. Branching here rather than
                # calling update_or_create avoids a second identical SELECT.
                profile = (
                    ProfileBlob.objects.select_for_update()
                    .filter(user_id=request.user.id)
                    .only("version")
                    .first()
                )
                if profile is None:
                    ProfileBlob.objects.create(
                        user_id=request.user.id, blob=raw, version=new_version
                    )
                elif new_version <= profile.version:
                    return error("stale_version", "Version must increase.", 409)
                else:
                    profile.blob = raw
                    profile.version = new_version
                    profile.save(update_fields=["blob", "version", "updated_date"])
        except IntegrityError:
            # select_for_update locks nothing when the row does not exist yet, so two
            # concurrent first-writes can both clear the version check above.
            return error("stale_version", "Version must increase.", 409)
        return Response(status=200)
