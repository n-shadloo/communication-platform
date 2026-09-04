from channels.db import database_sync_to_async

from api.auth import FULL, decode_access, load_device
from api.errors import ApiError


@database_sync_to_async
def authenticate_access(token_str):
    """Validate an access token through the one verifier, exactly as the HTTP
    surface does: full scope, a live device, an active account. Returns
    (user, device) on success, None on any failure."""
    try:
        claims = decode_access(token_str)
    except ApiError:
        return None
    if claims["scope"] != FULL:
        return None
    device = load_device(claims)
    if device is None:
        return None
    return device.user, device


def close_device_sockets(device_id):
    """Best-effort: tell the realtime consumer, if any, to drop this device's
    sockets. Safe no-op when none exists, and silent because the error would
    name a device id. Run 06 replaces the body when the gateway moves."""
    try:
        from asgiref.sync import async_to_sync
        from channels.layers import get_channel_layer

        layer = get_channel_layer()
        if layer:
            async_to_sync(layer.group_send)(
                f"dev.{device_id}", {"type": "connection.close"}
            )
    except Exception:
        pass


@database_sync_to_async
def delete_envelopes(device_id, ids):
    from messaging.models import QueuedEnvelope

    QueuedEnvelope.objects.filter(recipient_device_id=device_id, id__in=ids).delete()


@database_sync_to_async
def touch_active(device_id):
    from django.utils import timezone

    from devices.models import Device

    Device.objects.filter(id=device_id).update(last_active_date=timezone.now().date())


@database_sync_to_async
def _room_exists(room_id):
    from voicerooms.models import Room

    return Room.objects.filter(id=room_id).exists()


@database_sync_to_async
def room_join_async(room_id, device_id):
    from voicerooms.presence import room_join

    room_join(room_id, device_id)


@database_sync_to_async
def room_leave_async(room_id, device_id):
    from voicerooms.presence import room_leave

    room_leave(room_id, device_id)
