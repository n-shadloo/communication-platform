"""The synchronous units of work behind the key-backup route."""

import base64

from django.db import transaction

from accounts.models import User
from api.errors import ApiError
from vault.models import KeyBackup


def read(user_id):
    stored = KeyBackup.objects.filter(user_id=user_id).only("blob", "version").first()
    if stored is None:
        raise ApiError(404, "not_found", "No key backup yet.")
    return {
        "blob": base64.b64encode(bytes(stored.blob)).decode(),
        "version": stored.version,
    }


def write(user_id, raw, version):
    with transaction.atomic():
        # Lock the always-present owner row, not the KeyBackup row. On the first
        # upload the backup row does not exist, so select_for_update() on it
        # takes no lock: two concurrent first writes both read version=None, both
        # skip the check, and a lower version can clobber a higher one. Locking
        # the owner serialises first and subsequent writes alike.
        User.objects.select_for_update().filter(id=user_id).only("id").first()
        current = (
            KeyBackup.objects.filter(user_id=user_id)
            .values_list("version", flat=True)
            .first()
        )
        if current is not None and version <= current:
            raise ApiError(409, "stale_version", "Version must increase.")
        KeyBackup.objects.update_or_create(
            user_id=user_id, defaults={"blob": raw, "version": version}
        )
