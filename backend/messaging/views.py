import base64
import uuid

from django.db import transaction
from django.db.models import F
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.permissions import IsFullScope
from devices.models import Device

from .models import QueuedEnvelope
from .serializers import SendSerializer

MAX_DRAIN_LIMIT = 100
MAX_ACK_IDS = 200

DEVICE_SCOPE_REQUIRED = {"code": "device_scope_required",
                         "detail": "This endpoint requires a device-scoped token."}
BAD_REQUEST = {"code": "bad_request", "detail": "Malformed request."}


class SendEnvelopesView(APIView):
    """Accept a batch of {device_id, blob}. The authenticated sender is used ONLY for
    throttling and is written NOWHERE (§A5). Each recipient device gets an independent copy."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "envelopes"

    def post(self, request):
        ser = SendSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        items = ser.validated_data["messages"]
        target_ids = [i["device_id"] for i in items]
        live = set(Device.objects.filter(
            id__in=target_ids, revoked_date__isnull=True,
            user__is_active=True).values_list("id", flat=True))
        accepted = 0
        stale = []
        created = []
        for item in items:
            dev_id = item["device_id"]
            if dev_id not in live:
                stale.append(str(dev_id))
                continue
            with transaction.atomic():
                # The UPDATE takes a row lock held to commit, so a concurrent enqueue to
                # the same device blocks here and re-reads the incremented value; the
                # SELECT below sees this transaction's own write. That is what makes
                # (device, seq) collision-free without a global sequence (§A4).
                Device.objects.filter(id=dev_id).update(queue_seq=F("queue_seq") + 1)
                seq = Device.objects.filter(id=dev_id).values_list(
                    "queue_seq", flat=True).first()
                env = QueuedEnvelope.objects.create(
                    recipient_device_id=dev_id, seq=seq, blob=item["raw"])
            created.append((dev_id, env))
            accepted += 1
        self._push(created)
        return Response({"accepted": accepted, "stale_devices": stale},
                        status=status.HTTP_202_ACCEPTED)

    @staticmethod
    def _push(created):
        from messaging.services import _push
        _push(created)


class MyEnvelopesView(APIView):
    """Device drains its own mailbox, ascending by seq. Device scope required."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "envelopes"

    def get(self, request):
        device = getattr(request, "auth_device", None)
        if device is None:
            return Response(DEVICE_SCOPE_REQUIRED, status=403)
        limit = self._limit(request)
        rows = list(QueuedEnvelope.objects.filter(recipient_device_id=device.id)
                    .order_by("seq").only("id", "seq", "blob")[:limit + 1])
        has_more = len(rows) > limit
        rows = rows[:limit]
        return Response({
            "envelopes": [{"id": str(r.id), "seq": r.seq,
                           "blob": base64.b64encode(bytes(r.blob)).decode()} for r in rows],
            "has_more": has_more,
        })

    @staticmethod
    def _limit(request):
        """`?limit=abc` raises ValueError and `?limit=-5` parses fine and then poisons
        the slice — both 500s if the cap is applied the obvious way. §A5 caps at 100."""
        try:
            requested = int(request.query_params.get("limit", MAX_DRAIN_LIMIT))
        except (TypeError, ValueError):
            return MAX_DRAIN_LIMIT
        return max(1, min(requested, MAX_DRAIN_LIMIT))


class AckEnvelopesView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "envelopes"

    def post(self, request):
        device = getattr(request, "auth_device", None)
        if device is None:
            return Response(DEVICE_SCOPE_REQUIRED, status=403)
        # A JSON array body makes request.data a list, whose .get() is an AttributeError.
        if not isinstance(request.data, dict):
            return Response(BAD_REQUEST, status=400)
        ids = request.data.get("ids") or []
        if not isinstance(ids, list) or len(ids) > MAX_ACK_IDS:
            return Response(BAD_REQUEST, status=400)
        try:
            # Unparsed, a non-UUID id reaches the uuid column and raises Django's
            # ValidationError, which DRF does not handle — a 500 on malformed input.
            parsed = [uuid.UUID(str(i)) for i in ids]
        except (AttributeError, TypeError, ValueError):
            return Response(BAD_REQUEST, status=400)
        # Scoped to the calling device: DeviceJWTAuthentication has already proven the
        # device belongs to this user, and ids outside it simply match nothing.
        deleted, _ = QueuedEnvelope.objects.filter(
            recipient_device_id=device.id, id__in=parsed).delete()
        return Response({"deleted": deleted})
