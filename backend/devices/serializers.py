import base64
import binascii

from rest_framework import serializers

from accounts.serializers import StrictSerializer
from core.buckets import DEVICELOG_BUCKETS, KEYPACKAGE_BUCKETS, LABEL_BUCKETS
from core.fields import decode_blob_or_400

PUBKEY_MIN, PUBKEY_MAX = 32, 256  # public-key byte-length sanity bounds (opaque otherwise)
# Ed25519 signatures are fixed-size, so an exact check rejects nothing a real client
# would send. This is a malformed-input guard, not a security control: the signature
# itself is stored and relayed, never verified (see SignedPrekeySerializer).
ED25519_SIG_LEN = 64
# ML-KEM-768 encapsulation keys are likewise fixed-size, so an exact length is used
# rather than widening PUBKEY_MAX (which correctly bounds X25519/Ed25519): a range
# check would accept nothing useful that the exact check rejects. Also a
# malformed-input guard, not a security control.
PQ_PUBKEY_LEN = 1184

# Base64 of the largest accepted payload plus padding headroom. Unbounded, a client
# could push an arbitrarily long string into b64decode before any length check runs
# (the pattern messaging/serializers.py already applies to envelope blobs).
MAX_PUBKEY_CHARS = 4 * ((PUBKEY_MAX + 2) // 3) + 8
MAX_SIG_CHARS = 4 * ((ED25519_SIG_LEN + 2) // 3) + 8
MAX_PQ_PUBKEY_CHARS = 4 * ((PQ_PUBKEY_LEN + 2) // 3) + 8
MAX_DEVICELOG_CHARS = 4 * ((max(DEVICELOG_BUCKETS) + 2) // 3) + 8
MAX_LABEL_CHARS = 4 * ((max(LABEL_BUCKETS) + 2) // 3) + 8
MAX_KEYPACKAGE_CHARS = 4 * ((max(KEYPACKAGE_BUCKETS) + 2) // 3) + 8

# PositiveIntegerField is a 32-bit signed column with a >= 0 check. Without an upper
# bound a larger int reaches the column and raises psycopg's DataError, a 500 on
# input the serializer was supposed to be filtering.
MAX_KEY_INT = 2147483647

# Registration accepts neither, because no valid value exists for either: the canonical
# device bundle covers `device_id`, and registration is what assigns it. Anything a
# client could put here would be a signature over bytes describing a different device,
# and storing one is worse than storing null — peers read null as "never cross-signed,
# withhold messages", but a cross_sig that later changes to the real one looks like a
# cross-signature change, which CLIENT_CONTRACT.md §D/§E requires them to treat as a
# safety-number event and block the conversation over. So the impossible state is made
# unrepresentable rather than merely optional.
PREMATURE_BUNDLE_FIELDS = {"cross_sig", "bundle_version"}
PREMATURE_BUNDLE_DETAIL = (
    "Not accepted at registration: the canonical device bundle covers device_id, which "
    "this request assigns, so no signature computed before the response can be valid. "
    "Send cross_sig and bundle_version to PUT /me/devices/{device_id}/prekeys once you "
    "have the device_id.")

MAX_OTPKS = 200
MAX_PQ_OTPKS = 100
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


def _b64_ed25519_sig(value, field):
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise serializers.ValidationError({field: "invalid base64"})
    if len(raw) != ED25519_SIG_LEN:
        raise serializers.ValidationError({field: "bad signature length"})
    return raw


def _b64_pq_pubkey(value, field):
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise serializers.ValidationError({field: "invalid base64"})
    if len(raw) != PQ_PUBKEY_LEN:
        raise serializers.ValidationError({field: "bad key length"})
    return raw


def _reject_duplicate_key_ids(otpks, field="otpks"):
    """`unique (device, key_id)` makes a repeated key_id inside one payload an
    IntegrityError from bulk_create, i.e. a 500 on malformed client input."""
    seen = {otpk["key_id"] for otpk in otpks}
    if len(seen) != len(otpks):
        raise serializers.ValidationError({field: "duplicate key_id"})


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


class PqOtpkSerializer(StrictSerializer):
    key_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PQ_PUBKEY_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["raw"] = _b64_pq_pubkey(data["pub"], "pub")
        return data


class PqSignedPrekeySerializer(StrictSerializer):
    """Same stance as SignedPrekeySerializer: the signature is stored and relayed,
    never verified — the client verifies it against the device identity key."""

    spk_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    pub = serializers.CharField(max_length=MAX_PQ_PUBKEY_CHARS, trim_whitespace=False)
    sig = serializers.CharField(max_length=MAX_SIG_CHARS, trim_whitespace=False)

    def validate(self, data):
        data["pub_raw"] = _b64_pq_pubkey(data["pub"], "pub")
        data["sig_raw"] = _b64_ed25519_sig(data["sig"], "sig")
        return data


class IdentitySerializer(StrictSerializer):
    """Cross-signing identity upload. Like every signature this server stores, the
    bytes are stored and relayed, never verified: master_sig binds the subkeys to
    the master key, and only clients — holding the out-of-band-confirmed master —
    can check that binding. The length checks are malformed-input guards, not
    security controls."""

    master_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS,
                                       trim_whitespace=False)
    self_signing_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS,
                                             trim_whitespace=False)
    user_signing_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS,
                                             trim_whitespace=False)
    master_sig = serializers.CharField(max_length=MAX_SIG_CHARS, trim_whitespace=False)
    version = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)

    def validate(self, data):
        data["master_raw"] = _b64_pubkey(data["master_pub"], "master_pub")
        data["self_signing_raw"] = _b64_pubkey(data["self_signing_pub"],
                                               "self_signing_pub")
        data["user_signing_raw"] = _b64_pubkey(data["user_signing_pub"],
                                               "user_signing_pub")
        data["master_sig_raw"] = _b64_ed25519_sig(data["master_sig"], "master_sig")
        return data


class RegisterDeviceSerializer(StrictSerializer):
    ik_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    spk_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    spk_pub = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    spk_sig = serializers.CharField(max_length=MAX_PUBKEY_CHARS, trim_whitespace=False)
    registration_id = serializers.IntegerField(min_value=0, max_value=MAX_KEY_INT)
    # cross_sig and bundle_version are deliberately absent — see PREMATURE_BUNDLE_FIELDS
    # and to_internal_value below.
    pq_spk = PqSignedPrekeySerializer(required=False)
    pq_otpks = serializers.ListField(child=PqOtpkSerializer(),
                                     max_length=MAX_PQ_OTPKS, allow_empty=True,
                                     required=False, default=list)
    label_blob = serializers.CharField(required=False, allow_null=True,
                                       max_length=MAX_LABEL_CHARS, trim_whitespace=False)
    otpks = serializers.ListField(child=OtpkSerializer(), max_length=MAX_OTPKS,
                                  allow_empty=True)
    keypackages = serializers.ListField(
        child=serializers.CharField(max_length=MAX_KEYPACKAGE_CHARS,
                                    trim_whitespace=False),
        max_length=MAX_KEYPACKAGES, allow_empty=True)

    def to_internal_value(self, data):
        """Reject the cross-signature fields with an answer, not just a refusal.

        StrictSerializer would already reject them as unknown, but "Unexpected
        field." on an endpoint that required `cross_sig` until recently reads like a
        version mismatch and sends the reader hunting. Naming the reason and the
        right endpoint costs eight lines and saves that.
        """
        if isinstance(data, dict):
            premature = sorted(PREMATURE_BUNDLE_FIELDS & set(data))
            if premature:
                raise serializers.ValidationError(
                    {name: PREMATURE_BUNDLE_DETAIL for name in premature})
        return super().to_internal_value(data)

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
        _reject_duplicate_key_ids(data["pq_otpks"], field="pq_otpks")
        return data


class PrekeyReplenishSerializer(StrictSerializer):
    # Rotating the spk changes a signed bundle field, so the stored cross_sig goes
    # stale; the client is expected to send a fresh cross_sig and bundle_version in
    # the same call. The server stores whatever it is given without coupling the
    # two — enforcing the pairing here would be fake enforcement of a property only
    # peers can actually check.
    spk = SignedPrekeySerializer(required=False)
    cross_sig = serializers.CharField(required=False, max_length=MAX_SIG_CHARS,
                                      trim_whitespace=False)
    bundle_version = serializers.IntegerField(required=False, min_value=0,
                                              max_value=MAX_KEY_INT)
    pq_spk = PqSignedPrekeySerializer(required=False)
    pq_otpks = serializers.ListField(child=PqOtpkSerializer(),
                                     max_length=MAX_PQ_OTPKS, allow_empty=True,
                                     required=False, default=list)
    otpks = serializers.ListField(child=OtpkSerializer(), max_length=MAX_OTPKS,
                                  allow_empty=True, required=False, default=list)

    def validate(self, data):
        # Same pairing guard as registration, and load-bearing here for the same
        # reason: this endpoint is where a device's first cross_sig arrives, since
        # registration cannot carry one. A signature stored against bundle_version
        # 0 is one peers must reject, so half a pair is caught as malformed input
        # rather than persisted. Not a security control — the server still never
        # checks that the signature matches the bundle, only peers can.
        if ("cross_sig" in data) != ("bundle_version" in data):
            raise serializers.ValidationError(
                {"cross_sig": "cross_sig and bundle_version must be sent together"})
        if "cross_sig" in data:
            data["cross_sig_raw"] = _b64_ed25519_sig(data["cross_sig"], "cross_sig")
        _reject_duplicate_key_ids(data["otpks"])
        _reject_duplicate_key_ids(data["pq_otpks"], field="pq_otpks")
        return data


class KeyPackageUploadSerializer(StrictSerializer):
    keypackages = serializers.ListField(
        child=serializers.CharField(max_length=MAX_KEYPACKAGE_CHARS,
                                    trim_whitespace=False),
        max_length=MAX_KEYPACKAGES, allow_empty=True, required=False, default=list)
    is_last_resort = serializers.BooleanField(required=False, default=False)

    def validate(self, data):
        data["kp_raws"] = [decode_blob_or_400(encoded, KEYPACKAGE_BUCKETS)
                           for encoded in data["keypackages"]]
        # One per device, replace-on-upload: a batch of last-resort packages has
        # no meaning, so reject it rather than silently keeping only one.
        if data["is_last_resort"] and len(data["kp_raws"]) != 1:
            raise serializers.ValidationError(
                {"is_last_resort": "exactly one last-resort keypackage"})
        return data


class DeviceLogAppendSerializer(StrictSerializer):
    """Record contents are client-defined ciphertext-shaped blobs; the only check
    is the bucket length. In particular the hash chain inside them is NOT
    validated here — see the append view."""

    class _Rec(StrictSerializer):
        blob = serializers.CharField(max_length=MAX_DEVICELOG_CHARS,
                                     trim_whitespace=False)

        def validate(self, data):
            data["raw"] = decode_blob_or_400(data["blob"], DEVICELOG_BUCKETS)
            return data

    records = serializers.ListField(child=_Rec(), min_length=1, max_length=50)


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
