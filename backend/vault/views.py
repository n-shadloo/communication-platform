import base64

from django.db import transaction
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.permissions import IsFullScope

from .models import KeyBackup
from .serializers import KeyBackupSerializer


class KeyBackupView(APIView):
    permission_classes = [IsAuthenticated, IsFullScope]
    throttle_scope = "accounts"

    def get(self, request):
        key_backup = (
            KeyBackup.objects.filter(user_id=request.user.id)
            .only("blob", "version")
            .first()
        )
        if key_backup is None:
            return Response({"code": "not_found"}, status=404)
        return Response(
            {
                "blob": base64.b64encode(bytes(key_backup.blob)).decode(),
                "version": key_backup.version,
            }
        )

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
            current = (
                KeyBackup.objects.filter(user_id=request.user.id)
                .values_list("version", flat=True)
                .first()
            )
            if current is not None and version <= current:
                return Response({"code": "stale_version"}, status=409)
            KeyBackup.objects.update_or_create(
                user_id=request.user.id, defaults={"blob": raw, "version": version}
            )
        return Response(status=200)
