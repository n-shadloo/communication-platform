import base64

import pytest

from accounts.models import User
from core.buckets import KEYPACKAGE_BUCKETS, LABEL_BUCKETS
from devices.models import Device, KeyPackage, OneTimePrekey

PASSWORD = "correct-horse-battery-staple"

DEVICES_URL = "/api/v1/me/devices"


def pubkey(seed=b"k"):
    """Base64 of a 32-byte opaque public key (serializers.PUBKEY_MIN)."""
    return base64.b64encode((seed * 32)[:32]).decode()


def label_blob(filler=b"L"):
    size = min(LABEL_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def keypackage_blob(filler=b"K"):
    size = min(KEYPACKAGE_BUCKETS)
    return base64.b64encode((filler * size)[:size]).decode()


def register_payload(otpks=1, keypackages=0, **overrides):
    payload = {
        "ik_pub": pubkey(b"i"),
        "spk_id": 1,
        "spk_pub": pubkey(b"s"),
        "spk_sig": pubkey(b"g"),
        "registration_id": 1234,
        "otpks": [{"key_id": i, "pub": pubkey(bytes([65 + (i % 26)]))}
                  for i in range(otpks)],
        "keypackages": [keypackage_blob(bytes([65 + (i % 26)]))
                        for i in range(keypackages)],
    }
    payload.update(overrides)
    return payload


def make_device(user, registration_id=1, **kwargs):
    return Device.objects.create(
        user=user, ik_pub=b"ik" * 16, spk_id=1, spk_pub=b"sp" * 16,
        spk_sig=b"sg" * 16, registration_id=registration_id, **kwargs)


def stock_prekeys(device, count, start=0):
    OneTimePrekey.objects.bulk_create([
        OneTimePrekey(device=device, key_id=start + i, pub=b"p" * 32)
        for i in range(count)])


def stock_keypackages(device, count):
    KeyPackage.objects.bulk_create([
        KeyPackage(device=device, blob=b"k" * min(KEYPACKAGE_BUCKETS))
        for _ in range(count)])


@pytest.fixture
def peer(db):
    """Another activated account, whose public keys `active_user` will claim."""
    return User.objects.create_user(username="peer", password=PASSWORD, is_active=True)


@pytest.fixture
def peer_device(peer):
    return make_device(peer, registration_id=555)
