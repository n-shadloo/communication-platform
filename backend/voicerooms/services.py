"""The synchronous units of work behind the voice-room routes."""

import base64

from django.utils import timezone

from api.errors import ApiError
from voicerooms.models import Room

NOT_FOUND = "No such room."


def create(raw):
    room = Room.objects.create(name_blob=raw)
    return {"room_id": str(room.id)}


def read(room_id):
    """The room, without its live count: that lives in Redis and is read on the
    event loop, not here."""
    room = Room.objects.filter(id=room_id).only("id", "name_blob", "updated_date").first()
    if room is None:
        raise ApiError(404, "not_found", NOT_FOUND)
    return {
        "room_id": str(room.id),
        "name_blob": base64.b64encode(bytes(room.name_blob)).decode(),
        "updated_date": room.updated_date.isoformat(),
    }


def rename(room_id, raw):
    # auto_now never fires on a queryset .update(), so the rename bumps
    # updated_date explicitly; GET exposes it so peers notice renames. Still a
    # single UPDATE.
    updated = Room.objects.filter(id=room_id).update(
        name_blob=raw, updated_date=timezone.now().date()
    )
    if not updated:
        raise ApiError(404, "not_found", NOT_FOUND)


def require_room(room_id):
    if not Room.objects.filter(id=room_id).exists():
        raise ApiError(404, "not_found", NOT_FOUND)
