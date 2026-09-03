"""Repo-wide seizure/graph guard: the durable regression check.

Iterates every concrete model in the app registry and fails loudly if any model, in
any app, present or future, grows a plaintext column, key material, or a conversation
graph. `core/tests/test_manifest.py` is the narrower field manifest; this guard is
the stricter superset. Both stay: each is self-contained, so weakening one cannot
silently weaken the other.

The checks are pure module-level functions returning offender lists so they can be
driven outside this file (test_success_criteria.py, and break-the-guard proofs that
register a canary model and assert the function flags it).
"""

from django.apps import apps
from django.db.models import BinaryField
from django.test import SimpleTestCase

from core.fields import OpaqueBlobField

# Column names that would mean plaintext content, key material, or a stored graph.
# Checked against both the field name and its column attname, so an FK spelled
# `sender` cannot hide behind `sender_id`.
FORBIDDEN_FIELD_NAMES = frozenset(
    {
        "plaintext",
        "content",
        "message_text",
        "body",
        "private_key",
        "secret_key",
        "session_key",
        "media_key",
        "sframe_key",
        "room_key",
        "sender",
        "sender_id",
        "recipient_id",
        "recipients",
        "members",
        "membership",
        "roster",
        "group_members",
        "password_plain",
    }
)

# `password` holds an Argon2id hash: auth material, never a content key.
PASSWORD_ALLOWED_ON = frozenset({"accounts.User"})

# The framework tables are audited once. Django's `session_key` is the opaque id of
# an admin-only session (the API is token-auth), not key material. Nothing else is
# exempt, and a test below pins this set so it cannot quietly grow.
AUDITED_FRAMEWORK_COLUMNS = frozenset(
    {
        "sessions.Session.session_key",
    }
)

# This project's own apps: the tables a seizure of this backend would yield.
APP_LABELS = frozenset(
    {
        "accounts",
        "devices",
        "vault",
        "messaging",
        "attachments",
        "voicerooms",
        "core",
        "realtime",
    }
)

# Public halves of client keypairs are stored as plain BinaryFields: suffixed
# `_pub`/`_sig`, plus OneTimePrekey's bare `pub`.
PUBLIC_KEY_SUFFIXES = ("_pub", "_sig")
PUBLIC_KEY_NAMES = frozenset({"pub"})


def _label(model):
    return f"{model._meta.app_label}.{model.__name__}"


def _concrete_fields(model):
    """Declared columns and m2m fields; reverse accessors are not columns."""
    for field in model._meta.get_fields():
        if field.auto_created and not field.concrete:
            continue
        yield field


def forbidden_column_offenders():
    """No model may declare a plaintext/key/graph column."""
    offenders = []
    for model in apps.get_models():
        label = _label(model)
        for field in _concrete_fields(model):
            names = {field.name, getattr(field, "attname", field.name)}
            if any(f"{label}.{n}" in AUDITED_FRAMEWORK_COLUMNS for n in names):
                continue
            if names & FORBIDDEN_FIELD_NAMES:
                offenders.append(f"{label}.{field.name}")
            elif "password" in names and label not in PASSWORD_ALLOWED_ON:
                offenders.append(f"{label}.{field.name}")
    return offenders


def unbucketed_blob_offenders():
    """Every ciphertext field (`blob` / `*_blob`) is an OpaqueBlobField with a
    non-empty bucket_set; public-key byte fields may stay plain BinaryFields."""
    offenders = []
    for model in apps.get_models():
        for field in _concrete_fields(model):
            name = field.name
            if name.endswith(PUBLIC_KEY_SUFFIXES) or name in PUBLIC_KEY_NAMES:
                continue
            if name == "blob" or name.endswith("_blob"):
                if not isinstance(field, OpaqueBlobField):
                    offenders.append(f"{_label(model)}.{name}: {type(field).__name__}")
                elif not field.bucket_set:
                    offenders.append(f"{_label(model)}.{name}: empty bucket_set")
    return offenders


def raw_binary_offenders():
    """Belt-and-braces for this project's own tables: a BinaryField that is neither a
    declared public key nor an OpaqueBlobField is an unvalidated byte store, the
    exact shape a future plaintext/key column would take while dodging the name
    checks."""
    offenders = []
    for model in apps.get_models():
        if model._meta.app_label not in APP_LABELS:
            continue
        for field in _concrete_fields(model):
            if not isinstance(field, BinaryField):
                continue
            if isinstance(field, OpaqueBlobField):
                continue
            name = field.name
            if name.endswith(PUBLIC_KEY_SUFFIXES) or name in PUBLIC_KEY_NAMES:
                continue
            offenders.append(f"{_label(model)}.{name}")
    return offenders


def envelope_graph_offenders():
    """The envelope's only relation is to a recipient device: no sender in any
    spelling, structurally (sealed sender at rest)."""
    from messaging.models import QueuedEnvelope

    offenders = []
    fks = []
    for field in _concrete_fields(QueuedEnvelope):
        if "sender" in field.name or "sender" in getattr(field, "attname", ""):
            offenders.append(f"messaging.QueuedEnvelope.{field.name} mentions a sender")
        if field.is_relation:
            fks.append(field)
    if [
        f"{fk.related_model._meta.app_label}.{fk.related_model.__name__}" for fk in fks
    ] != ["devices.Device"]:
        offenders.append(
            "messaging.QueuedEnvelope must have exactly one relation, to devices.Device; "
            f"found {[fk.name for fk in fks]}"
        )
    return offenders


def dual_user_fk_offenders():
    """Outside `accounts`, no table may hold two references to users: the shape that
    would encode a sender-recipient pair at rest. history/keybackup/attachment each
    reference only their owner/uploader."""
    from accounts.models import User

    offenders = []
    for model in apps.get_models():
        if model._meta.app_label == "accounts":
            continue
        user_fks = [
            f.name
            for f in _concrete_fields(model)
            if f.is_relation and f.related_model is User
        ]
        if len(user_fks) > 1:
            offenders.append(f"{_label(model)}: {user_fks}")
    return offenders


class SeizureGuardTests(SimpleTestCase):
    """One test per invariant."""

    def test_no_model_declares_a_plaintext_key_or_graph_column(self):
        self.assertEqual(
            forbidden_column_offenders(),
            [],
            "A model grew a column this architecture forbids",
        )

    def test_every_ciphertext_field_is_an_exact_bucket_opaque_blob(self):
        self.assertEqual(
            unbucketed_blob_offenders(),
            [],
            "Every stored blob must be OpaqueBlobField with buckets",
        )

    def test_no_app_table_holds_unclassified_binary_data(self):
        self.assertEqual(
            raw_binary_offenders(),
            [],
            "A raw BinaryField outside the public-key set appeared",
        )

    def test_envelopes_have_no_sender_and_route_only_to_a_device(self):
        self.assertEqual(
            envelope_graph_offenders(), [], "Sealed sender at rest was broken"
        )

    def test_no_table_outside_accounts_references_users_twice(self):
        self.assertEqual(
            dual_user_fk_offenders(), [], "A sender-recipient-shaped table appeared"
        )

    def test_the_framework_exemption_list_cannot_quietly_grow(self):
        self.assertEqual(
            AUDITED_FRAMEWORK_COLUMNS,
            {"sessions.Session.session_key"},
            "Every new exemption needs an audit entry and review here",
        )

    def test_the_guard_actually_sees_this_schema(self):
        # Anti-vacuity: introspection must be walking the real registry. If any known
        # table or ciphertext column stops being visible, the guard itself is broken.
        seen = {_label(m) for m in apps.get_models()}
        self.assertLessEqual(
            {
                "accounts.User",
                "accounts.ProfileBlob",
                "devices.Device",
                "devices.OneTimePrekey",
                "devices.PqOneTimePrekey",
                "devices.DeviceLogRecord",
                "devices.UserIdentity",
                "vault.KeyBackup",
                "messaging.QueuedEnvelope",
                "attachments.Attachment",
                "voicerooms.Room",
            },
            seen,
        )
        blob_names = {
            f"{_label(m)}.{f.name}"
            for m in apps.get_models()
            for f in _concrete_fields(m)
            if isinstance(f, OpaqueBlobField)
        }
        self.assertLessEqual(
            {
                "accounts.ProfileBlob.blob",
                "devices.Device.label_blob",
                "devices.DeviceLogRecord.blob",
                "vault.KeyBackup.blob",
                "messaging.QueuedEnvelope.blob",
                "voicerooms.Room.name_blob",
            },
            blob_names,
        )
