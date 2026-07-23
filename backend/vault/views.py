import base64

from django.db import transaction
from django.db.models import BigIntegerField, Count, F, Func, Max, Sum, Value
from django.db.models.functions import Coalesce
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.permissions import IsFullScope

from .models import HistoryRecord, KeyBackup
from .serializers import HistoryAppendSerializer, KeyBackupSerializer

BAD_REQUEST = {"code": "bad_request"}


class KeyBackupView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request):
        key_backup = KeyBackup.objects.filter(user_id=request.user.id).only(
            "blob", "version").first()
        if key_backup is None:
            return Response({"code": "not_found"}, status=404)
        return Response({"blob": base64.b64encode(bytes(key_backup.blob)).decode(),
                         "version": key_backup.version})

    def put(self, request):
        serializer = KeyBackupSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        raw = serializer.validated_data["raw"]
        version = serializer.validated_data["version"]

        with transaction.atomic():
            # Lock the always-present owner row, not the KeyBackup row. On the first
            # upload the backup row does not exist, so select_for_update() on it takes
            # no lock: two concurrent first writes both read version=None, both skip
            # the check, and a lower version can clobber a higher one. Locking the
            # owner serialises first and subsequent writes alike.
            User.objects.select_for_update().filter(id=request.user.id).only("id").first()
            current = KeyBackup.objects.filter(
                user_id=request.user.id).values_list("version", flat=True).first()
            if current is not None and version <= current:
                return Response({"code": "stale_version"}, status=409)
            KeyBackup.objects.update_or_create(
                user_id=request.user.id, defaults={"blob": raw, "version": version})
        return Response(status=200)


class HistoryView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    MAX_LIMIT = 500

    def get(self, request):
        # int("abc") raises and a negative limit poisons the slice and has_more, both
        # 500s if parsed naively. A bad cursor falls back to reading from the start; a
        # bad or oversized limit clamps into [1, MAX_LIMIT].
        after = self._int(request.query_params.get("after"), -1)
        limit = max(1, min(self._int(request.query_params.get("limit"), self.MAX_LIMIT),
                           self.MAX_LIMIT))

        rows = list(HistoryRecord.objects.filter(
            owner_id=request.user.id, seq__gt=after).order_by("seq").only(
            "seq", "blob")[:limit + 1])
        has_more = len(rows) > limit
        rows = rows[:limit]

        return Response({
            "records": [{"seq": row.seq,
                         "blob": base64.b64encode(bytes(row.blob)).decode()}
                        for row in rows],
            "has_more": has_more,
        })

    def post(self, request):
        serializer = HistoryAppendSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        records = serializer.validated_data["records"]

        with transaction.atomic():
            # Serialise appends for this owner by locking the owner row.
            User.objects.select_for_update().filter(id=request.user.id).only("id").first()
            current = HistoryRecord.objects.filter(owner_id=request.user.id).aggregate(
                m=Max("seq"))["m"]
            start = (current if current is not None else -1) + 1
            rows = [HistoryRecord(owner_id=request.user.id, seq=start + i,
                                  blob=record["raw"])
                    for i, record in enumerate(records)]
            HistoryRecord.objects.bulk_create(rows)

        return Response({"first_seq": start, "last_seq": start + len(records) - 1},
                        status=201)

    @staticmethod
    def _int(value, default):
        try:
            return int(value)
        except (TypeError, ValueError):
            return default


class HistoryDeleteView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def post(self, request):
        # A JSON array body makes request.data a list, whose .get() is an AttributeError.
        if not isinstance(request.data, dict):
            return Response(BAD_REQUEST, status=400)
        if request.data.get("all") is True:
            deleted, _ = HistoryRecord.objects.filter(owner_id=request.user.id).delete()
            return Response({"deleted": deleted})

        seqs = request.data.get("seqs")
        if not isinstance(seqs, list) or len(seqs) > 1000:
            return Response(BAD_REQUEST, status=400)
        try:
            # A non-int in `seqs` reaches the bigint column and raises inside the DB
            # driver, so coerce up front. OverflowError covers a JSON 1e400, which the
            # parser hands over as float inf.
            parsed = [int(s) for s in seqs]
        except (TypeError, ValueError, OverflowError):
            return Response(BAD_REQUEST, status=400)

        deleted, _ = HistoryRecord.objects.filter(
            owner_id=request.user.id, seq__in=parsed).delete()
        return Response({"deleted": deleted})


class HistoryUsageView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request):
        # One aggregate query: octet_length(blob) is summed DB-side, never loading a
        # blob into Python. Coalesce keeps an empty log at 0 rather than NULL, and the
        # BigIntegerField output stops a large total overflowing.
        agg = HistoryRecord.objects.filter(owner_id=request.user.id).aggregate(
            records=Count("id"),
            bytes=Coalesce(
                Sum(Func(F("blob"), function="OCTET_LENGTH",
                         output_field=BigIntegerField())),
                Value(0), output_field=BigIntegerField()))
        return Response({"records": agg["records"], "bytes": agg["bytes"]})
