from django.apps import apps
from django.test import SimpleTestCase

from core.fields import OpaqueBlobField

# Column names that would mean the server had grown a plaintext store, key material, or a
# conversation graph (ARCHITECTURE §A11.1–3). None of these may ever exist on any model.
FORBIDDEN_FIELD_NAMES = frozenset({
    "plaintext", "content", "message_text", "body",
    "private_key", "secret_key", "session_key",
    "sender", "sender_id", "recipient_id",
    "members", "membership", "roster",
    "password_plain",
})

# `password` holds an Argon2id hash: auth material, not a content key (§A12). It is
# legitimate on the user model and nowhere else.
PASSWORD_ALLOWED_ON = frozenset({"accounts.User"})

# §A4 audits the framework tables once and accepts them. Django's `session_key` is an
# opaque session identifier used only by the admin — the API is token-only — and is not
# key material under the §A12 inventory. Nothing else gets an exemption.
AUDITED_FRAMEWORK_COLUMNS = frozenset({
    "sessions.Session.session_key",
})

# Public halves of client keypairs are explicitly fine to store and are not bucketed
# ciphertext, so they stay plain BinaryFields (§A4).
PUBLIC_KEY_SUFFIXES = ("_pub", "_sig")


def columns(model):
    """Concrete columns and m2m fields — reverse accessors are not columns."""
    for field in model._meta.get_fields():
        if field.auto_created and not field.concrete:
            continue
        yield field


def label_of(model):
    return f"{model._meta.app_label}.{model.__name__}"


def blob_fields():
    for model in apps.get_models():
        for field in columns(model):
            name = field.name
            if name.endswith(PUBLIC_KEY_SUFFIXES):
                continue
            if name == "blob" or name.endswith("_blob"):
                yield label_of(model), field


class FieldManifestTests(SimpleTestCase):
    """The field-manifest guard. It introspects every registered model and fails loudly
    if a later phase introduces a column this architecture forbids."""

    def test_no_model_declares_a_forbidden_column(self):
        offenders = []
        for model in apps.get_models():
            label = label_of(model)
            for field in columns(model):
                name = field.name
                if f"{label}.{name}" in AUDITED_FRAMEWORK_COLUMNS:
                    continue
                if name in FORBIDDEN_FIELD_NAMES:
                    offenders.append(f"{label}.{name}")
                elif name == "password" and label not in PASSWORD_ALLOWED_ON:
                    offenders.append(f"{label}.{name}")

        self.assertEqual(
            offenders, [],
            "Forbidden columns found — this server stores no plaintext, no key material, "
            f"and no conversation graph (ARCHITECTURE §A11): {offenders}",
        )

    def test_every_ciphertext_field_is_a_bucketed_opaque_blob(self):
        problems = []
        for label, field in blob_fields():
            if not isinstance(field, OpaqueBlobField):
                problems.append(
                    f"{label}.{field.name} is {type(field).__name__}, expected OpaqueBlobField"
                )
            elif not field.bucket_set:
                problems.append(f"{label}.{field.name} has an empty bucket_set")

        self.assertEqual(
            problems, [],
            f"Every stored blob must be exact-bucket-validated (ARCHITECTURE §A7): {problems}",
        )

    def test_guard_actually_sees_the_known_ciphertext_fields(self):
        # Without this the two checks above would pass vacuously if introspection broke.
        found = {f"{label}.{field.name}" for label, field in blob_fields()}

        self.assertIn("accounts.ProfileBlob.blob", found)
        self.assertIn("devices.Device.label_blob", found)
