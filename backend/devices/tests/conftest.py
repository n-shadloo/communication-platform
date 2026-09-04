import base64

import pytest
from django.db import connection

from accounts.models import User
from core.buckets import LABEL_BUCKETS
from devices.models import (
    Device,
    OneTimePrekey,
    PqOneTimePrekey,
    UserIdentity,
)
from devices.serializers import PQ_PUBKEY_LEN

PASSWORD = "correct-horse-battery-staple"

DEVICES_URL = "/api/v1/me/devices"


def connect_then_wait(barrier):
    """Open this thread's database connection before it waits at the barrier.

    Connection setup costs 10-20 ms and varies by thread — more than the whole
    transaction a race test is about, and `CONN_MAX_AGE` is 0, so every unit of work
    opens its own. Threads released together would otherwise reach the row one at a
    time on a slow runner, and what the guard proves would depend on the machine
    instead of on the lock.
    """
    connection.ensure_connection()
    barrier.wait(timeout=10)


def pubkey(seed=b"k"):
    """Base64 of a 32-byte opaque public key (serializers.PUBKEY_MIN)."""
    return base64.b64encode((seed * 32)[:32]).decode()


def label_blob(filler=b"L"):
    size = min(LABEL_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def cross_sig_b64(seed=b"x"):
    """Base64 of a 64-byte Ed25519 signature stand-in (opaque to the server)."""
    return base64.b64encode((seed * 64)[:64]).decode()


def register_payload(otpks=1, **overrides):
    payload = {
        "ik_pub": pubkey(b"i"),
        "spk_id": 1,
        "spk_pub": pubkey(b"s"),
        "spk_sig": pubkey(b"g"),
        "registration_id": 1234,
        # No cross_sig/bundle_version: the endpoint refuses them, because the bundle
        # they sign covers the device_id this call assigns. Cross-signing happens in
        # the follow-up PUT .../prekeys call.
        "otpks": [
            {"key_id": i, "pub": pubkey(bytes([65 + (i % 26)]))} for i in range(otpks)
        ],
    }
    payload.update(overrides)
    return payload


def publish_identity(user, version=1):
    """Registration past the first device requires a published identity; tests
    that add devices to an already-provisioned account call this first."""
    return UserIdentity.objects.create(
        user=user,
        master_pub=b"m" * 32,
        self_signing_pub=b"s" * 32,
        user_signing_pub=b"u" * 32,
        master_sig=b"g" * 64,
        version=version,
    )


def make_device(user, registration_id=1, **kwargs):
    return Device.objects.create(
        user=user,
        ik_pub=b"ik" * 16,
        spk_id=1,
        spk_pub=b"sp" * 16,
        spk_sig=b"sg" * 16,
        registration_id=registration_id,
        **kwargs,
    )


def pq_pubkey(seed=b"q"):
    """Base64 of an exactly-1184-byte ML-KEM-768 encapsulation key stand-in."""
    return base64.b64encode((seed * PQ_PUBKEY_LEN)[:PQ_PUBKEY_LEN]).decode()


def stock_prekeys(device, count, start=0):
    OneTimePrekey.objects.bulk_create(
        [
            OneTimePrekey(device=device, key_id=start + i, pub=b"p" * 32)
            for i in range(count)
        ]
    )


def stock_pq_prekeys(device, count, start=0):
    PqOneTimePrekey.objects.bulk_create(
        [
            PqOneTimePrekey(device=device, key_id=start + i, pub=b"q" * PQ_PUBKEY_LEN)
            for i in range(count)
        ]
    )


@pytest.fixture
def peer(db):
    """Another activated account, whose public keys `active_user` will claim."""
    return User.objects.create_user(username="peer", password=PASSWORD, is_active=True)


@pytest.fixture
def peer_device(peer):
    return make_device(peer, registration_id=555)
