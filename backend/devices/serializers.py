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
# bound a larger int reaches the column and raises psycopg's DataError — a 500 on
# input the serializer was supposed to be filtering.
MAX_KEY_INT = 2147483647

MAX_OTPKS = 200        # §A5 `otpks:[{key_id,pub}]≤200`
MAX_KEYPACKAGES = 100  # §A5 `keypackages:[blob]≤100`
# A user is capped at 10 devices (§A4), so a larger id list can only ever be noise;
# the bound keeps an oversized `IN (...)` out of the planner.
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
    seen = {o["key_id"] for o in otpks}
    if len(seen) != len(otpks):
        raise serializers.ValidationError({"otpks": "duplicate key_id"})


class OtpkSerializer(StrictSerializer):
    key_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)

    def validate(self, d):
        d["raw"] = _b64_pubkey(d["pub"], "pub")
        return d


class SignedPrekeySerializer(StrictSerializer):
    """§A5's `spk?:{spk_id,pub,sig}`.

    The signature is stored and relayed, never verified: checking it would mean the
    server parsing key material and committing to a curve it has no business knowing
    (§A11.2, §A12), and the client is the party that must verify spk_sig against
    ik_pub as part of X3DH. Validating it here would imply a guarantee the server
    does not keep (§A14).
    """

    spk_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    sig = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)

    def validate(self, d):
        d["pub_raw"] = _b64_pubkey(d["pub"], "pub")
        d["sig_raw"] = _b64_pubkey(d["sig"], "sig")
        return d


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

    def validate(self, d):
        d["ik_raw"] = _b64_pubkey(d["ik_pub"], "ik_pub")
        d["spk_raw"] = _b64_pubkey(d["spk_pub"], "spk_pub")
        d["spk_sig_raw"] = _b64_pubkey(d["spk_sig"], "spk_sig")
        if d.get("label_blob"):
            d["label_raw"] = decode_blob_or_400(d["label_blob"], LABEL_BUCKETS)
        else:
            d["label_raw"] = None
        d["kp_raws"] = [decode_blob_or_400(b, KEYPACKAGE_BUCKETS) for b in d["keypackages"]]
        _reject_duplicate_key_ids(d["otpks"])
        return d


class PrekeyReplenishSerializer(StrictSerializer):
    """§A5's `PUT /me/devices/{id}/prekeys` body — `{spk?, otpks:[...]}`."""

    spk = SignedPrekeySerializer(required=False)
    otpks = serializers.ListField(child=OtpkSerializer(), max_length=MAX_OTPKS,
                                  allow_empty=True, required=False, default=list)

    def validate(self, d):
        _reject_duplicate_key_ids(d["otpks"])
        return d


class KeyPackageUploadSerializer(StrictSerializer):
    keypackages = serializers.ListField(
        child=serializers.CharField(max_length=MAX_KEYPACKAGE_CHARS,
                                    trim_whitespace=False),
        max_length=MAX_KEYPACKAGES, allow_empty=True, required=False, default=list)

    def validate(self, d):
        d["kp_raws"] = [decode_blob_or_400(b, KEYPACKAGE_BUCKETS)
                        for b in d["keypackages"]]
        return d


class ClaimSerializer(StrictSerializer):
    """`{device_ids?}`. Parsed as UUIDs rather than passed through: an unparsed value
    reaching a uuid column raises Django's ValidationError, which DRF does not handle
    — a 500 on malformed input."""

    device_ids = serializers.ListField(child=serializers.UUIDField(),
                                       max_length=MAX_CLAIM_DEVICE_IDS,
                                       allow_empty=True, required=False)


class LabelUpdateSerializer(StrictSerializer):
    label_blob = serializers.CharField(max_length=MAX_LABEL_CHARS, trim_whitespace=False)

    def validate(self, d):
        d["label_raw"] = decode_blob_or_400(d["label_blob"], LABEL_BUCKETS)
        return d
