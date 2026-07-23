import base64
import binascii

from rest_framework import serializers

from accounts.serializers import StrictSerializer
from core.buckets import KEYPACKAGE_BUCKETS, LABEL_BUCKETS
from core.fields import decode_blob_or_400

PUBKEY_MIN, PUBKEY_MAX = 32, 256  # public-key byte-length sanity bounds (opaque otherwise)

# Base64 of the largest accepted payload plus padding headroom. Unbounded, a client
# could push an arbitrarily long string into b64decode before any length check runs
# (the pattern messaging/serializers.py already applies to envelope blobs).
MAX_PUBKEY_CHARS = 4 * ((PUBKEY_MAX + 2) // 3) + 8
MAX_LABEL_CHARS = 4 * ((max(LABEL_BUCKETS) + 2) // 3) + 8
MAX_KEYPACKAGE_CHARS = 4 * ((max(KEYPACKAGE_BUCKETS) + 2) // 3) + 8

# PositiveIntegerField is a 32-bit signed column with a >= 0 check. Without an upper
# bound a larger int reaches the column and raises psycopg's DataError, a 500 on
# input the serializer was supposed to be filtering.
MAX_KEY_INT = 2147483647

MAX_OTPKS = 200
MAX_KEYPACKAGES = 100
# Accounts hold at most MAX_DEVICES_PER_USER devices, so a longer id list can only
# be noise; the bound keeps an oversized `IN (...)` out of the planner.
MAX_CLAIM_DEVICE_IDS = 100


def _b64_pubkey(value, field):
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise serializers.ValidationError({field: "invalid base64"})
    if not (PUBKEY_MIN <= len(raw) <= PUBKEY_MAX):
        raise serializers.ValidationError({field: "bad key length"})
    return raw


def _reject_duplicate_key_ids(otpks):
    """`unique (device, key_id)` makes a repeated key_id inside one payload an
    IntegrityError from bulk_create, i.e. a 500 on malformed client input."""
    seen = {otpk["key_id"] for otpk in otpks}
    if len(seen) != len(otpks):
        raise serializers.ValidationError({"otpks": "duplicate key_id"})


class OtpkSerializer(StrictSerializer):
    key_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["raw"] = _b64_pubkey(data["pub"], "pub")
        return data


class SignedPrekeySerializer(StrictSerializer):
    """The signature is stored and relayed, never verified: checking it would mean
    the server parsing key material and committing to a curve, and the client is the
    party that must verify spk_sig against ik_pub as part of X3DH. Validating it
    here would imply a guarantee the server does not keep."""

    spk_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    sig = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["pub_raw"] = _b64_pubkey(data["pub"], "pub")
        data["sig_raw"] = _b64_pubkey(data["sig"], "sig")
        return data


class RegisterDeviceSerializer(StrictSerializer):
    ik_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    spk_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    spk_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    spk_sig = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    registration_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    label_blob = serializers.CharField(required=False, allow_null=True,
                                       max_length=MAX_LABEL_CHARS, trim_whitespace=False)
    otpks = serializers.ListField(child=OtpkSerializer(), max_length=MAX_OTPKS,
                                  allow_empty=True)
    keypackages = serializers.ListField(
        child=serializers.CharField(max_length=MAX_KEYPACKAGE_CHARS,
                                    trim_whitespace=False),
        max_length=MAX_KEYPACKAGES, allow_empty=True)

    def validate(self, data):
        data["ik_raw"] = _b64_pubkey(data["ik_pub"], "ik_pub")
        data["spk_raw"] = _b64_pubkey(data["spk_pub"], "spk_pub")
        data["spk_sig_raw"] = _b64_pubkey(data["spk_sig"], "spk_sig")
        if data.get("label_blob"):
            data["label_raw"] = decode_blob_or_400(data["label_blob"], LABEL_BUCKETS)
        else:
            data["label_raw"] = None
        data["kp_raws"] = [decode_blob_or_400(encoded, KEYPACKAGE_BUCKETS)
                           for encoded in data["keypackages"]]
        _reject_duplicate_key_ids(data["otpks"])
        return data


class PrekeyReplenishSerializer(StrictSerializer):
    spk = SignedPrekeySerializer(required=False)
    otpks = serializers.ListField(child=OtpkSerializer(), max_length=MAX_OTPKS,
                                  allow_empty=True, required=False, default=list)

    def validate(self, data):
        _reject_duplicate_key_ids(data["otpks"])
        return data


class KeyPackageUploadSerializer(StrictSerializer):
    keypackages = serializers.ListField(
        child=serializers.CharField(max_length=MAX_KEYPACKAGE_CHARS,
                                    trim_whitespace=False),
        max_length=MAX_KEYPACKAGES, allow_empty=True, required=False, default=list)

    def validate(self, data):
        data["kp_raws"] = [decode_blob_or_400(encoded, KEYPACKAGE_BUCKETS)
                           for encoded in data["keypackages"]]
        return data


class ClaimSerializer(StrictSerializer):
    """`{device_ids?}`. Parsed as UUIDs rather than passed through: an unparsed value
    reaching a uuid column raises Django's ValidationError, which DRF does not
    handle, a 500 on malformed input."""

    device_ids = serializers.ListField(child=serializers.UUIDField(),
                                       max_length=MAX_CLAIM_DEVICE_IDS,
                                       allow_empty=True, required=False)


class LabelUpdateSerializer(StrictSerializer):
    label_blob = serializers.CharField(max_length=MAX_LABEL_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["label_raw"] = decode_blob_or_400(data["label_blob"], LABEL_BUCKETS)
        return data
