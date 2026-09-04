"""The database half of the gateway: the token check and the three writes.

Each unit of work is a module-level synchronous function that opens no
transaction of its own and never awaits, and each has a thin `async` wrapper that
runs it through `api/orm.py`. That is the same shape every FastAPI route uses,
for the same reason: the ORM is synchronous, and a call to it from the event loop
raises. Splitting the pair also keeps the unit measurable — `tests/
test_query_counts.py` counts the queries of the synchronous half directly, which
it cannot do through the wrapper, because the wrapper's connection bracket closes
the connection the test's own transaction holds.
"""

from api.auth import FULL, decode_access, load_device
from api.errors import ApiError
from api.orm import run_unit


def _authenticate_access(token_str):
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


def _delete_envelopes(device_id, ids):
    from messaging.models import QueuedEnvelope

    QueuedEnvelope.objects.filter(recipient_device_id=device_id, id__in=ids).delete()


def _touch_active(device_id):
    from django.utils import timezone

    from devices.models import Device

    Device.objects.filter(id=device_id).update(last_active_date=timezone.now().date())


def _room_exists(room_id):
    from voicerooms.models import Room

    return Room.objects.filter(id=room_id).exists()


async def authenticate_access(token_str):
    return await run_unit(_authenticate_access, token_str)


async def delete_envelopes(device_id, ids):
    return await run_unit(_delete_envelopes, device_id, ids)


async def touch_active(device_id):
    return await run_unit(_touch_active, device_id)


async def room_exists(room_id):
    return await run_unit(_room_exists, room_id)
