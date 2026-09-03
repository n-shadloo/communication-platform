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

DEVICE_SCOPE_REQUIRED = {
    "code": "device_scope_required",
    "detail": "This endpoint requires a device-scoped token.",
}
BAD_REQUEST = {"code": "bad_request", "detail": "Malformed request."}


class SendEnvelopesView(APIView):
    """Accepts a batch of {device_id, blob} items. The sender is used only for
    throttling and is never written; each recipient device gets its own copy."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "envelopes"

    def post(self, request):
        serializer = SendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        messages = serializer.validated_data["messages"]

        target_ids = [message["device_id"] for message in messages]
        live = set(
            Device.objects.filter(
                id__in=target_ids, revoked_date__isnull=True, user__is_active=True
            ).values_list("id", flat=True)
        )

        accepted = 0
        stale = []
        created = []
        for message in messages:
            device_id = message["device_id"]
            if device_id not in live:
                stale.append(str(device_id))
                continue
            with transaction.atomic():
                # The UPDATE holds a row lock until commit, so a concurrent enqueue
                # blocks and re-reads the incremented value. This is what keeps
                # (device, seq) unique without a global sequence.
                Device.objects.filter(id=device_id).update(queue_seq=F("queue_seq") + 1)
                seq = (
                    Device.objects.filter(id=device_id)
                    .values_list("queue_seq", flat=True)
                    .first()
                )
                envelope = QueuedEnvelope.objects.create(
                    recipient_device_id=device_id, seq=seq, blob=message["raw"]
                )
            created.append((device_id, envelope))
            accepted += 1

        self._push(created)
        return Response(
            {"accepted": accepted, "stale_devices": stale},
            status=status.HTTP_202_ACCEPTED,
        )

    @staticmethod
    def _push(created):
        from messaging.services import _push

        _push(created)


class MyEnvelopesView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "envelopes"

    def get(self, request):
        device = getattr(request, "auth_device", None)
        if device is None:
            return Response(DEVICE_SCOPE_REQUIRED, status=403)

        limit = self._limit(request)
        rows = list(
            QueuedEnvelope.objects.filter(recipient_device_id=device.id)
            .order_by("seq")
            .only("id", "seq", "blob")[: limit + 1]
        )
        has_more = len(rows) > limit
        rows = rows[:limit]

        return Response(
            {
                "envelopes": [
                    {
                        "id": str(row.id),
                        "seq": row.seq,
                        "blob": base64.b64encode(bytes(row.blob)).decode(),
                    }
                    for row in rows
                ],
                "has_more": has_more,
                # A client whose last acked seq is below this lost envelopes to the
                # TTL prune — possibly ratchet messages or control events — and must
                # repair the affected pairwise sessions (CLIENT_CONTRACT.md §H).
                "pruned_through": device.queue_pruned_through,
            }
        )

    @staticmethod
    def _limit(request):
        """A non-numeric limit raises ValueError and a negative one poisons the
        slice, so clamp into [1, MAX_DRAIN_LIMIT] rather than trusting int()."""
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
            # A non-UUID id would raise Django's ValidationError at the uuid column,
            # which DRF does not catch, so parse before it reaches the queryset.
            parsed = [uuid.UUID(str(i)) for i in ids]
        except (AttributeError, TypeError, ValueError):
            return Response(BAD_REQUEST, status=400)

        deleted, _ = QueuedEnvelope.objects.filter(
            recipient_device_id=device.id, id__in=parsed
        ).delete()
        return Response({"deleted": deleted})
