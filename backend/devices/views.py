import base64
import hashlib

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.permissions import IsFullScope
from accounts.tokens import issue_full

from .models import Device, KeyPackage, OneTimePrekey
from .serializers import (ClaimSerializer, KeyPackageUploadSerializer,
                          LabelUpdateSerializer, PrekeyReplenishSerializer,
                          RegisterDeviceSerializer)

# Without a stored cap, replenishment is an unbounded write primitive for any
# authenticated device.
MAX_STORED_KEYPACKAGES = 100
MAX_STORED_OTPKS = 200

FORBIDDEN = {"code": "forbidden",
             "detail": "This token does not belong to that device."}


def error(code, detail, status_code):
    return Response({"code": code, "detail": detail}, status=status_code)


def _device_list_etag(user_id):
    """One query over the account's live device set.

    Live-only on purpose: hashing revoked rows too would still change the tag on
    every add/remove/revoke, but it would also give an account whose devices were
    all revoked a different tag from an account that never had any, while both
    serve the same empty list. Any authenticated peer can read that difference,
    and it leaks device churn the peer list deliberately hides.

    `user__is_active` matches the peer view's filter: without it a deactivation
    would leave the tag unchanged and every polling peer would sit on a 304
    holding devices the list no longer returns.
    """
    rows = list(Device.objects.filter(user_id=user_id, user__is_active=True,
                                      revoked_date__isnull=True)
                .values_list("id", flat=True).order_by("id"))
    digest = hashlib.sha256(repr(rows).encode()).hexdigest()
    return f'"{digest[:32]}"'


class MyDevicesView(APIView):
    """POST registers a device, GET lists this account's devices.

    A register-scope token's entire power is reaching the registration endpoint,
    so the scope check is per-method: POST opts down to IsAuthenticated, everything
    else keeps the project-wide IsFullScope. A register token must never read the
    device list.
    """

    throttle_scope = "accounts"

    def get_permissions(self):
        if self.request.method == "POST":
            return [IsAuthenticated()]
        return [IsAuthenticated(), IsFullScope()]

    def post(self, request):
        serializer = RegisterDeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            # Lock the account row, not the device rows. select_for_update() on a
            # .count() is silently dropped by Django when it builds the aggregate,
            # and even a real row lock over existing devices would not block a
            # concurrent INSERT.
            User.objects.select_for_update().filter(pk=request.user.id).only("id").first()
            count = Device.objects.filter(
                user_id=request.user.id, revoked_date__isnull=True).count()
            if count >= settings.MAX_DEVICES_PER_USER:
                return error("device_limit", "This account has too many devices.", 409)
            device = Device.objects.create(
                user_id=request.user.id,
                ik_pub=data["ik_raw"], spk_id=data["spk_id"], spk_pub=data["spk_raw"],
                spk_sig=data["spk_sig_raw"], registration_id=data["registration_id"],
                label_blob=data["label_raw"])  # spk_updated_date is auto_now_add
            if data["otpks"]:
                OneTimePrekey.objects.bulk_create([
                    OneTimePrekey(device=device, key_id=otpk["key_id"], pub=otpk["raw"])
                    for otpk in data["otpks"]])
            if data["kp_raws"]:
                KeyPackage.objects.bulk_create([
                    KeyPackage(device=device, blob=raw) for raw in data["kp_raws"]])

        access, refresh = issue_full(request.user, device)
        return Response({"device_id": str(device.id), "access": access,
                         "refresh": refresh, "scope": "full"},
                        status=status.HTTP_201_CREATED)

    def get(self, request):
        this_id = getattr(getattr(request, "auth_device", None), "id", None)
        etag = _device_list_etag(request.user.id)
        if request.headers.get("If-None-Match") == etag:
            return Response(status=status.HTTP_304_NOT_MODIFIED)

        devices = Device.objects.filter(
            user_id=request.user.id, revoked_date__isnull=True).only(
            # created_date is day-coarse, so it alone leaves same-day devices in an
            # arbitrary order that can shuffle between polls; id breaks the tie.
            "id", "label_blob", "created_date", "last_active_date").order_by(
            "created_date", "id")
        data = [{
            "device_id": str(device.id),
            "label_blob": base64.b64encode(bytes(device.label_blob)).decode() if device.label_blob else None,
            "created_date": device.created_date.isoformat(),
            "last_active_date": device.last_active_date.isoformat() if device.last_active_date else None,
            "this_device": (device.id == this_id),
        } for device in devices]

        resp = Response({"devices": data})
        resp["ETag"] = etag
        return resp


class MyDeviceDetailView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def put(self, request, device_id):
        serializer = LabelUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        updated = Device.objects.filter(
            id=device_id, user_id=request.user.id, revoked_date__isnull=True
        ).update(label_blob=serializer.validated_data["label_raw"])
        if not updated:
            return error("not_found", "No such device.", 404)
        return Response(status=200)

    def delete(self, request, device_id):
        with transaction.atomic():
            device = Device.objects.select_for_update().filter(
                id=device_id, user_id=request.user.id, revoked_date__isnull=True).first()
            if device is None:
                return error("not_found", "No such device.", 404)
            device.revoked_date = timezone.now().date()
            device.token_generation += 1  # invalidates all outstanding tokens
            device.save(update_fields=["revoked_date", "token_generation"])
            OneTimePrekey.objects.filter(device=device).delete()
            KeyPackage.objects.filter(device=device).delete()
            device.queue.all().delete()  # its mailbox

        self._close_sockets(device_id)
        return Response(status=status.HTTP_204_NO_CONTENT)

    @staticmethod
    def _close_sockets(device_id):
        """Best-effort: tell the realtime consumer, if any, to drop this device's
        sockets. Safe no-op when none exists."""
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            layer = get_channel_layer()
            if layer:
                async_to_sync(layer.group_send)(
                    f"dev.{device_id}", {"type": "connection.close"})
        except Exception:
            pass


class _OwnDeviceView(APIView):
    """Shared gate for the endpoints only the device itself may use: the token's
    device_id must equal the path device."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def _reject_other_device(self, request, device_id):
        auth_device = getattr(request, "auth_device", None)
        if auth_device is None or str(auth_device.id) != str(device_id):
            return Response(FORBIDDEN, status=403)
        return None


class MyPrekeysView(_OwnDeviceView):
    def put(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        serializer = PrekeyReplenishSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        spk = data.get("spk")

        with transaction.atomic():
            # The device row exists (authentication proved it), so this lock is real
            # and serialises two concurrent replenishments against the stored cap.
            Device.objects.select_for_update().filter(pk=device_id).only("id").first()
            # Cap first, mutate second. Returning a Response from inside atomic() is
            # not an exception, so the transaction commits: checking after the spk
            # write would leave a device told "409, nothing stored" with its signed
            # prekey rotated anyway, and peers fetching an spk the client believes
            # was never installed.
            stored = OneTimePrekey.objects.filter(device_id=device_id).count()
            if stored + len(data["otpks"]) > MAX_STORED_OTPKS:
                return error("prekey_limit",
                             "Too many stored one-time prekeys for this device.", 409)
            if spk:
                Device.objects.filter(pk=device_id).update(
                    spk_id=spk["spk_id"], spk_pub=spk["pub_raw"],
                    spk_sig=spk["sig_raw"], spk_updated_date=timezone.now().date())
            if data["otpks"]:
                # ignore_conflicts: re-uploading a key_id the device already stored is
                # an idempotent retry, not an error.
                OneTimePrekey.objects.bulk_create([
                    OneTimePrekey(device_id=device_id, key_id=otpk["key_id"],
                                  pub=otpk["raw"])
                    for otpk in data["otpks"]], ignore_conflicts=True)
            count = OneTimePrekey.objects.filter(device_id=device_id).count()
        return Response({"otpk_count": count})


class MyPrekeysCountView(_OwnDeviceView):
    def get(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        return Response({"otpk_count": OneTimePrekey.objects.filter(
            device_id=device_id).count()})


class MyKeyPackagesView(_OwnDeviceView):
    def put(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        serializer = KeyPackageUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raws = serializer.validated_data["kp_raws"]

        with transaction.atomic():
            Device.objects.select_for_update().filter(pk=device_id).only("id").first()
            stored = KeyPackage.objects.filter(device_id=device_id).count()
            if stored + len(raws) > MAX_STORED_KEYPACKAGES:
                return error("keypackage_limit",
                             "Too many stored key packages for this device.", 409)
            if raws:
                KeyPackage.objects.bulk_create(
                    [KeyPackage(device_id=device_id, blob=raw) for raw in raws])
            count = KeyPackage.objects.filter(device_id=device_id).count()
        return Response({"keypackage_count": count})


class MyKeyPackagesCountView(_OwnDeviceView):
    def get(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        return Response({"keypackage_count": KeyPackage.objects.filter(
            device_id=device_id).count()})


class PeerDevicesView(APIView):
    """Public identity + registration id of another user's live devices, with an ETag."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request, user_id):
        etag = _device_list_etag(user_id)
        if request.headers.get("If-None-Match") == etag:
            return Response(status=status.HTTP_304_NOT_MODIFIED)

        devices = Device.objects.filter(
            user_id=user_id, revoked_date__isnull=True, user__is_active=True).only(
            "id", "ik_pub", "registration_id").order_by("id")
        data = [{"device_id": str(device.id),
                 "ik_pub": base64.b64encode(bytes(device.ik_pub)).decode(),
                 "registration_id": device.registration_id} for device in devices]

        resp = Response({"devices": data, "etag": etag})
        resp["ETag"] = etag
        return resp


class _ClaimView(APIView):
    """Shared target resolution for the two claim endpoints."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "claim"

    @staticmethod
    def _targets(request, user_id, fields):
        serializer = ClaimSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        qs = Device.objects.filter(user_id=user_id, revoked_date__isnull=True,
                                   user__is_active=True)
        # Presence, not truthiness: an explicit `device_ids: []` asks for no devices.
        # Treating it as "all" would silently burn a one-time prekey on every device.
        if "device_ids" in serializer.validated_data:
            qs = qs.filter(id__in=serializer.validated_data["device_ids"])
        return qs.only(*fields).order_by("id")


class ClaimKeysView(_ClaimView):
    """Return an X3DH bundle per requested live device, consuming one one-time prekey
    each (deleted transactionally, skip_locked so a claim can never hand the same OTPK
    twice)."""

    def post(self, request, user_id):
        targets = self._targets(request, user_id, (
            "id", "registration_id", "ik_pub", "spk_id", "spk_pub", "spk_sig"))
        bundles = []
        for device in targets:
            otpk = None
            with transaction.atomic():
                row = (OneTimePrekey.objects.select_for_update(skip_locked=True)
                       .filter(device_id=device.id).order_by("key_id").first())
                if row is not None:
                    otpk = {"key_id": row.key_id,
                            "pub": base64.b64encode(bytes(row.pub)).decode()}
                    row.delete()
            bundle = {
                "device_id": str(device.id),
                "registration_id": device.registration_id,
                "ik_pub": base64.b64encode(bytes(device.ik_pub)).decode(),
                "spk_id": device.spk_id,
                "spk_pub": base64.b64encode(bytes(device.spk_pub)).decode(),
                "spk_sig": base64.b64encode(bytes(device.spk_sig)).decode(),
            }
            if otpk:
                bundle["otpk"] = otpk
            bundles.append(bundle)
        return Response({"bundles": bundles})


class ClaimKeyPackagesView(_ClaimView):
    def post(self, request, user_id):
        targets = self._targets(request, user_id, ("id",))
        out = []
        for device in targets:
            with transaction.atomic():
                row = (KeyPackage.objects.select_for_update(skip_locked=True)
                       .filter(device_id=device.id).order_by("created_date", "id").first())
                if row is not None:
                    out.append({"device_id": str(device.id),
                                "blob": base64.b64encode(bytes(row.blob)).decode()})
                    row.delete()
        return Response({"keypackages": out})
