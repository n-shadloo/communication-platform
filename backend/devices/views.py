import base64
import hashlib

from django.conf import settings
from django.db import transaction
from django.db.models import Max
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.permissions import IsFullScope
from accounts.tokens import issue_full

from .models import (Device, DeviceLogRecord, KeyPackage, OneTimePrekey,
                     PqOneTimePrekey, UserIdentity)
from .serializers import (ClaimSerializer, DeviceLogAppendSerializer,
                          IdentitySerializer, KeyPackageUploadSerializer,
                          LabelUpdateSerializer, PrekeyReplenishSerializer,
                          RegisterDeviceSerializer)

# Without a stored cap, replenishment is an unbounded write primitive for any
# authenticated device.
MAX_STORED_KEYPACKAGES = 100
MAX_STORED_OTPKS = 200
# 100 × 1184 B per device keeps the worst-case PQ pool ≈ 24 MB across the whole
# deployment (20 users × 10 devices); the cap is a storage budget, do not raise it.
MAX_STORED_PQ_OTPKS = 100

FORBIDDEN = {"code": "forbidden",
             "detail": "This token does not belong to that device."}


def error(code, detail, status_code):
    return Response({"code": code, "detail": detail}, status=status_code)


def _device_list_etag(user_id):
    """One query over the account's live device set, one over its log head.
    Returns (etag, log_head_seq) so callers surface the head without re-querying.

    Live-only on purpose: hashing revoked rows too would still change the tag on
    every add/remove/revoke, but it would also give an account whose devices were
    all revoked a different tag from an account that never had any, while both
    serve the same empty list. Any authenticated peer can read that difference,
    and it leaks device churn the peer list deliberately hides.

    `user__is_active` matches the peer view's filter: without it a deactivation
    would leave the tag unchanged and every polling peer would sit on a 304
    holding devices the list no longer returns. The log-head query carries the
    same filter for the same reason.

    The head record's blob hash is an input alongside the live device id set: a
    log append must change the tag, or a polling peer would sit on a 304 and
    never see the new head it is supposed to gossip.
    """
    rows = list(Device.objects.filter(user_id=user_id, user__is_active=True,
                                      revoked_date__isnull=True)
                .values_list("id", flat=True).order_by("id"))
    head = (DeviceLogRecord.objects
            .filter(user_id=user_id, user__is_active=True)
            .order_by("-seq").values_list("seq", "blob").first())
    head_hash = hashlib.sha256(bytes(head[1])).hexdigest() if head else None
    digest = hashlib.sha256(repr((rows, head_hash)).encode()).hexdigest()
    return f'"{digest[:32]}"', (head[0] if head else None)


def _b64_or_none(value):
    return base64.b64encode(bytes(value)).decode() if value else None


class MyIdentityView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def put(self, request):
        serializer = IdentitySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            # Lock the always-present User row, not the identity row: on the first
            # publish the identity row does not exist yet, so select_for_update()
            # on it would take no lock and two concurrent first publishes could
            # both pass the version check (the same reasoning as vault's
            # KeyBackupView.put). The version check itself is anti-accident — it
            # stops a stale client clobbering a newer identity — not a security
            # control: a modified server would simply not apply it, and clients
            # must detect identity changes on their own.
            User.objects.select_for_update().filter(pk=request.user.id).only("id").first()
            current = UserIdentity.objects.filter(
                user_id=request.user.id).values_list("version", flat=True).first()
            if current is not None and data["version"] <= current:
                return Response({"code": "stale_version"}, status=409)
            UserIdentity.objects.update_or_create(
                user_id=request.user.id,
                defaults={"master_pub": data["master_raw"],
                          "self_signing_pub": data["self_signing_raw"],
                          "user_signing_pub": data["user_signing_raw"],
                          "master_sig": data["master_sig_raw"],
                          "version": data["version"]})
        return Response(status=200)


class PeerIdentityView(APIView):
    """Serve a user's cross-signing identity verbatim. No smoothing, no history:
    if the stored master key changed, peers get the new bytes and must raise their
    own alarm — hiding or merging a change here would defeat exactly the check the
    clients are required to make."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request, user_id):
        # user__is_active matches PeerDevicesView: a deactivated account publishes
        # nothing.
        identity = UserIdentity.objects.filter(
            user_id=user_id, user__is_active=True).only(
            "master_pub", "self_signing_pub", "user_signing_pub", "master_sig",
            "version").first()
        if identity is None:
            return Response({"code": "not_found"}, status=404)
        return Response({
            "master_pub": base64.b64encode(bytes(identity.master_pub)).decode(),
            "self_signing_pub": base64.b64encode(
                bytes(identity.self_signing_pub)).decode(),
            "user_signing_pub": base64.b64encode(
                bytes(identity.user_signing_pub)).decode(),
            "master_sig": base64.b64encode(bytes(identity.master_sig)).decode(),
            "version": identity.version,
        })


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
            # A published identity is a precondition of registration — but only
            # once the account has a live device. The first device is exempt by
            # necessity: register-scope tokens reach exactly this endpoint, so a
            # fresh account cannot publish an identity before registering (the
            # client publishes immediately after, with the full token issued
            # below). This is a completeness check against a mis-sequenced
            # client, NOT a security control: a
            # modified server would simply not apply it, and peers must treat a
            # device with no verifiable identity chain as unverified regardless.
            if count and not UserIdentity.objects.filter(
                    user_id=request.user.id).exists():
                return error("identity_required",
                             "Publish a cross-signing identity before adding "
                             "another device.", 400)
            pq_spk = data.get("pq_spk")
            device = Device.objects.create(
                user_id=request.user.id,
                ik_pub=data["ik_raw"], spk_id=data["spk_id"], spk_pub=data["spk_raw"],
                spk_sig=data["spk_sig_raw"], registration_id=data["registration_id"],
                # cross_sig/bundle_version are not settable here and the serializer
                # refuses them: the client cannot sign a bundle whose device_id this
                # INSERT is about to mint, and a later device cannot reach its
                # self-signing key without the token issued below. The row is born in
                # the model-default "never cross-signed" state (null/0) that peers
                # already refuse, and the client cross-signs via the prekeys endpoint
                # as its next call (CLIENT_CONTRACT.md §M).
                pq_spk_id=pq_spk["spk_id"] if pq_spk else None,
                pq_spk_pub=pq_spk["pub_raw"] if pq_spk else None,
                pq_spk_sig=pq_spk["sig_raw"] if pq_spk else None,
                pq_spk_updated_date=timezone.now().date() if pq_spk else None,
                label_blob=data["label_raw"])  # spk_updated_date is auto_now_add
            if data["otpks"]:
                OneTimePrekey.objects.bulk_create([
                    OneTimePrekey(device=device, key_id=otpk["key_id"], pub=otpk["raw"])
                    for otpk in data["otpks"]])
            if data["pq_otpks"]:
                PqOneTimePrekey.objects.bulk_create([
                    PqOneTimePrekey(device=device, key_id=otpk["key_id"],
                                    pub=otpk["raw"])
                    for otpk in data["pq_otpks"]])
            if data["kp_raws"]:
                KeyPackage.objects.bulk_create([
                    KeyPackage(device=device, blob=raw) for raw in data["kp_raws"]])

        access, refresh = issue_full(request.user, device)
        return Response({"device_id": str(device.id), "access": access,
                         "refresh": refresh, "scope": "full"},
                        status=status.HTTP_201_CREATED)

    def get(self, request):
        this_id = getattr(getattr(request, "auth_device", None), "id", None)
        etag, log_head_seq = _device_list_etag(request.user.id)
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

        resp = Response({"devices": data, "log_head_seq": log_head_seq})
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
            PqOneTimePrekey.objects.filter(device=device).delete()
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

        pq_spk = data.get("pq_spk")

        with transaction.atomic():
            # The device row exists (authentication proved it), so this lock is real
            # and serialises two concurrent replenishments against the stored cap.
            Device.objects.select_for_update().filter(pk=device_id).only("id").first()
            # Cap first, mutate second. Returning a Response from inside atomic() is
            # not an exception, so the transaction commits: checking after the spk
            # write would leave a device told "409, nothing stored" with its signed
            # prekey rotated anyway, and peers fetching an spk the client believes
            # was never installed. Both caps are checked before either write for the
            # same reason.
            stored = OneTimePrekey.objects.filter(device_id=device_id).count()
            if stored + len(data["otpks"]) > MAX_STORED_OTPKS:
                return error("prekey_limit",
                             "Too many stored one-time prekeys for this device.", 409)
            if data["pq_otpks"]:
                pq_stored = PqOneTimePrekey.objects.filter(device_id=device_id).count()
                if pq_stored + len(data["pq_otpks"]) > MAX_STORED_PQ_OTPKS:
                    return error(
                        "prekey_limit",
                        "Too many stored PQ one-time prekeys for this device.", 409)
            # One UPDATE for the signed-bundle fields. Rotating the spk stales the
            # stored cross_sig, so a rotating client is expected to send a fresh
            # cross_sig and bundle_version in the same call; the server stores what
            # it is given and never checks the pairing — only peers can.
            bundle_updates = {}
            if spk:
                bundle_updates.update(
                    spk_id=spk["spk_id"], spk_pub=spk["pub_raw"],
                    spk_sig=spk["sig_raw"], spk_updated_date=timezone.now().date())
            if pq_spk:
                bundle_updates.update(
                    pq_spk_id=pq_spk["spk_id"], pq_spk_pub=pq_spk["pub_raw"],
                    pq_spk_sig=pq_spk["sig_raw"],
                    pq_spk_updated_date=timezone.now().date())
            if "cross_sig_raw" in data:
                bundle_updates["cross_sig"] = data["cross_sig_raw"]
            if "bundle_version" in data:
                bundle_updates["bundle_version"] = data["bundle_version"]
            if bundle_updates:
                Device.objects.filter(pk=device_id).update(**bundle_updates)
            if data["otpks"]:
                # ignore_conflicts: re-uploading a key_id the device already stored is
                # an idempotent retry, not an error.
                OneTimePrekey.objects.bulk_create([
                    OneTimePrekey(device_id=device_id, key_id=otpk["key_id"],
                                  pub=otpk["raw"])
                    for otpk in data["otpks"]], ignore_conflicts=True)
            if data["pq_otpks"]:
                PqOneTimePrekey.objects.bulk_create([
                    PqOneTimePrekey(device_id=device_id, key_id=otpk["key_id"],
                                    pub=otpk["raw"])
                    for otpk in data["pq_otpks"]], ignore_conflicts=True)
            count = OneTimePrekey.objects.filter(device_id=device_id).count()
        return Response({"otpk_count": count})


class MyPrekeysCountView(_OwnDeviceView):
    def get(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        return Response({
            "otpk_count": OneTimePrekey.objects.filter(
                device_id=device_id).count(),
            "pq_otpk_count": PqOneTimePrekey.objects.filter(
                device_id=device_id).count(),
        })


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
            if serializer.validated_data["is_last_resort"]:
                # Replace-on-upload keeps the cap at one last-resort package per
                # device, and keeps re-uploading after a reinstall idempotent.
                # It lives outside the consumable cap: it is never deleted by a
                # claim, so counting it against the pool would permanently
                # shrink the pool by one.
                KeyPackage.objects.filter(device_id=device_id,
                                          is_last_resort=True).delete()
                KeyPackage.objects.create(device_id=device_id, blob=raws[0],
                                          is_last_resort=True)
            else:
                stored = KeyPackage.objects.filter(
                    device_id=device_id, is_last_resort=False).count()
                if stored + len(raws) > MAX_STORED_KEYPACKAGES:
                    return error("keypackage_limit",
                                 "Too many stored key packages for this device.", 409)
                if raws:
                    KeyPackage.objects.bulk_create(
                        [KeyPackage(device_id=device_id, blob=raw) for raw in raws])
            # The count is the consumable pool — the client replenishes on this
            # number, and the everlasting last-resort row would mask exhaustion.
            count = KeyPackage.objects.filter(device_id=device_id,
                                              is_last_resort=False).count()
        return Response({"keypackage_count": count})


class MyKeyPackagesCountView(_OwnDeviceView):
    def get(self, request, device_id):
        denied = self._reject_other_device(request, device_id)
        if denied is not None:
            return denied
        return Response({"keypackage_count": KeyPackage.objects.filter(
            device_id=device_id, is_last_resort=False).count()})


class MyDeviceLogView(APIView):
    """Append client-signed device-list log records.

    The server must not verify the hash chain: a record whose prev_hash links to
    nothing is accepted and served verbatim. Chain validation here would be fake
    enforcement — a modified server (the adversary) would simply not apply it, and
    its existence would train clients to skip the head comparison that actually
    detects equivocation. The server's whole contribution is assigning seq and
    serving bytes back unchanged.
    """

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def post(self, request):
        serializer = DeviceLogAppendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        records = serializer.validated_data["records"]

        with transaction.atomic():
            # Serialise appends for this user by locking the user row.
            User.objects.select_for_update().filter(id=request.user.id).only("id").first()
            current = DeviceLogRecord.objects.filter(
                user_id=request.user.id).aggregate(m=Max("seq"))["m"]
            start = (current if current is not None else -1) + 1
            rows = [DeviceLogRecord(user_id=request.user.id, seq=start + i,
                                    blob=record["raw"])
                    for i, record in enumerate(records)]
            DeviceLogRecord.objects.bulk_create(rows)

        return Response({"first_seq": start, "last_seq": start + len(records) - 1},
                        status=201)


class PeerDeviceLogView(APIView):
    """Keyset-paged read of a user's device-list log, served verbatim: no repair,
    no reordering, no dropping of records that fail to link — see MyDeviceLogView
    for why the server never validates the chain."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    MAX_LIMIT = 200

    def get(self, request, user_id):
        # int("abc") raises and a negative limit poisons the slice and has_more,
        # both 500s if parsed naively. A bad cursor falls back to reading from the
        # start; a bad or oversized limit clamps into [1, MAX_LIMIT].
        after = self._int(request.query_params.get("after"), -1)
        limit = max(1, min(self._int(request.query_params.get("limit"),
                                     self.MAX_LIMIT), self.MAX_LIMIT))

        base = DeviceLogRecord.objects.filter(user_id=user_id,
                                              user__is_active=True)
        rows = list(base.filter(seq__gt=after).order_by("seq").only(
            "seq", "blob")[:limit + 1])
        has_more = len(rows) > limit
        rows = rows[:limit]
        head_seq = base.aggregate(m=Max("seq"))["m"]

        return Response({
            "records": [{"seq": row.seq,
                         "blob": base64.b64encode(bytes(row.blob)).decode()}
                        for row in rows],
            "has_more": has_more,
            "head_seq": head_seq,
        })

    @staticmethod
    def _int(value, default):
        try:
            return int(value)
        except (TypeError, ValueError):
            return default


class PeerDevicesView(APIView):
    """Public identity + registration id of another user's live devices, with an ETag."""

    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request, user_id):
        etag, log_head_seq = _device_list_etag(user_id)
        if request.headers.get("If-None-Match") == etag:
            return Response(status=status.HTTP_304_NOT_MODIFIED)

        devices = Device.objects.filter(
            user_id=user_id, revoked_date__isnull=True, user__is_active=True).only(
            "id", "ik_pub", "registration_id", "cross_sig",
            "bundle_version").order_by("id")
        # cross_sig is surfaced verbatim, null included: a device that was never
        # cross-signed must be visible as such so peers can refuse it. Substituting
        # or defaulting anything here would forge exactly the attestation the
        # design keeps out of the server's hands.
        data = [{"device_id": str(device.id),
                 "ik_pub": base64.b64encode(bytes(device.ik_pub)).decode(),
                 "registration_id": device.registration_id,
                 "cross_sig": _b64_or_none(device.cross_sig),
                 "bundle_version": device.bundle_version} for device in devices]

        resp = Response({"devices": data, "etag": etag,
                         "log_head_seq": log_head_seq})
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
            "id", "registration_id", "ik_pub", "spk_id", "spk_pub", "spk_sig",
            "cross_sig", "bundle_version", "pq_spk_id", "pq_spk_pub", "pq_spk_sig"))
        bundles = []
        for device in targets:
            otpk = None
            pq_otpk = None
            with transaction.atomic():
                row = (OneTimePrekey.objects.select_for_update(skip_locked=True)
                       .filter(device_id=device.id).order_by("key_id").first())
                if row is not None:
                    otpk = {"key_id": row.key_id,
                            "pub": base64.b64encode(bytes(row.pub)).decode()}
                    row.delete()
                # A PQ one-time prekey is only consumed alongside the signed PQ
                # prekey: without pq_spk the bundle is classical-only anyway, and
                # burning a stored PQ key for it would waste the key without ever
                # serving PQ material.
                if device.pq_spk_pub:
                    pq_row = (PqOneTimePrekey.objects
                              .select_for_update(skip_locked=True)
                              .filter(device_id=device.id).order_by("key_id").first())
                    if pq_row is not None:
                        pq_otpk = {"key_id": pq_row.key_id,
                                   "pub": base64.b64encode(bytes(pq_row.pub)).decode()}
                        pq_row.delete()
            bundle = {
                "device_id": str(device.id),
                "registration_id": device.registration_id,
                "ik_pub": base64.b64encode(bytes(device.ik_pub)).decode(),
                "spk_id": device.spk_id,
                "spk_pub": base64.b64encode(bytes(device.spk_pub)).decode(),
                "spk_sig": base64.b64encode(bytes(device.spk_sig)).decode(),
                # Verbatim, null included — an unsigned device must look unsigned.
                "cross_sig": _b64_or_none(device.cross_sig),
                "bundle_version": device.bundle_version,
            }
            # When a device holds no PQ material the PQ fields are omitted entirely,
            # never defaulted or zero-filled: a classical-only bundle must be
            # visibly classical-only. Deciding whether to refuse it or flag the
            # session is the client's job (CLIENT_CONTRACT.md) — quietly making the
            # bundle look complete here would remove exactly the signal that
            # decision needs.
            if device.pq_spk_pub:
                bundle["pq_spk_id"] = device.pq_spk_id
                bundle["pq_spk_pub"] = base64.b64encode(
                    bytes(device.pq_spk_pub)).decode()
                bundle["pq_spk_sig"] = base64.b64encode(
                    bytes(device.pq_spk_sig)).decode()
                if pq_otpk:
                    bundle["pq_otpk"] = pq_otpk
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
                       .filter(device_id=device.id, is_last_resort=False)
                       .order_by("created_date", "id").first())
                if row is not None:
                    out.append({"device_id": str(device.id),
                                "blob": base64.b64encode(bytes(row.blob)).decode()})
                    row.delete()
                    continue
                # Pool exhausted: serve the last-resort package WITHOUT deleting
                # it, so the device can still be added to groups. Every join that
                # reuses it shares one KEM secret, so compromising that one key
                # later exposes each such join's Welcome — a real forward-secrecy
                # cost, and the reason this is the fallback and not the default.
                last = KeyPackage.objects.filter(
                    device_id=device.id, is_last_resort=True).order_by("id").first()
                if last is not None:
                    out.append({"device_id": str(device.id),
                                "blob": base64.b64encode(bytes(last.blob)).decode()})
        return Response({"keypackages": out})
