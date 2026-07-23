import base64

from django.conf import settings
from django.utils import timezone
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsFullScope

from .livekit import mint_join_token
from .models import Room
from .presence import room_live_count
from .serializers import RoomNameSerializer

# The CRUD views share the general per-user "accounts" throttle scope; the token mint
# has its own tighter "roomtoken" scope.


class RoomListCreateView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def post(self, request):
        serializer = RoomNameSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        room = Room.objects.create(name_blob=serializer.validated_data["raw"])
        return Response({"room_id": str(room.id)}, status=201)


class RoomDetailView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request, room_id):
        room = Room.objects.filter(id=room_id).only(
            "id", "name_blob", "updated_date").first()
        if room is None:
            return Response({"code": "not_found"}, status=404)
        return Response({
            "room_id": str(room.id),
            "name_blob": base64.b64encode(bytes(room.name_blob)).decode(),
            "updated_date": room.updated_date.isoformat(),
            "live_count": room_live_count(room.id),
        })

    def put(self, request, room_id):
        serializer = RoomNameSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # auto_now never fires on a queryset .update(), so the rename bumps
        # updated_date explicitly; GET exposes it so peers notice renames. Still a
        # single UPDATE.
        updated = Room.objects.filter(id=room_id).update(
            name_blob=serializer.validated_data["raw"],
            updated_date=timezone.now().date())
        return Response(status=200 if updated else 404)


class RoomTokenView(APIView):
    """Mint a LiveKit join token for this room and this device. Requires a
    device-scoped token. The server never joins the media path."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "roomtoken"

    def post(self, request, room_id):
        device = getattr(request, "auth_device", None)
        if device is None:
            return Response({"code": "device_scope_required"}, status=403)
        if not Room.objects.filter(id=room_id).exists():
            return Response({"code": "not_found"}, status=404)
        if not (settings.LIVEKIT_URL and settings.LIVEKIT_API_KEY
                and settings.LIVEKIT_API_SECRET):
            return Response({"code": "voice_unconfigured"}, status=503)
        token, ttl = mint_join_token(room_id, device.id)
        return Response({"url": settings.LIVEKIT_URL, "token": token, "expires_in": ttl})
