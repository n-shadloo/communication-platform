from channels.db import database_sync_to_async
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def authenticate_access(token_str):
    """Validate an access token exactly like DeviceJWTAuthentication: full scope and
    a live device required. Returns (user, device) on success, None on any failure."""
    from devices.models import Device

    try:
        token = AccessToken(token_str)  # signature + expiry
    except TokenError:
        return None
    if token.get("scope") != "full":
        return None
    try:
        device = Device.objects.select_related("user").get(
            id=token.get("device_id"),
            user_id=token.get("user_id"),
            revoked_date__isnull=True,
        )
    except Device.DoesNotExist:
        return None
    if token.get("tgen") != device.token_generation or not device.user.is_active:
        return None
    return device.user, device


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
