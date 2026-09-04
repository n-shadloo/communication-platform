"""The vault `AppConfig`.

Six lines, and two of them are load-bearing. The label is what every migration
dependency, every `db_table` prefix and every `apps.get_model` call in this
project spells; and the model set of this app is a design statement — the vault
holds one table, and a second one appearing here is how server-side history or a
per-write audit trail would arrive.
"""

from django.apps import AppConfig, apps
from django.conf import settings
from django.test import SimpleTestCase

from vault.apps import VaultConfig
from vault.models import KeyBackup


class VaultConfigTests(SimpleTestCase):
    def test_the_app_is_configured_under_the_label_the_settings_list_uses(self):
        config = apps.get_app_config("vault")

        self.assertIsInstance(config, VaultConfig)
        self.assertEqual(config.name, "vault")
        self.assertEqual(config.label, "vault")
        self.assertEqual(config.default_auto_field, "django.db.models.BigAutoField")

    def test_the_app_is_installed(self):
        self.assertIn("vault", settings.INSTALLED_APPS)

    def test_the_app_declares_exactly_one_model(self):
        """A second model in this app is either message history growing back or a
        per-write audit row — both of which the design forbids, and neither of
        which any other test would notice on the day it is added."""
        self.assertEqual(list(apps.get_app_config("vault").get_models()), [KeyBackup])

    def test_the_config_adds_no_ready_hook(self):
        """`ready()` is where an app binds signals or starts work at boot. This
        one inherits Django's no-op, so nothing in the vault runs outside a
        request — a `ready()` here would be a writer nobody asked for."""
        self.assertIs(VaultConfig.ready, AppConfig.ready)

    def test_importing_the_package_itself_runs_nothing(self):
        self.assertEqual((settings.BASE_DIR / "vault" / "__init__.py").read_text(), "")
