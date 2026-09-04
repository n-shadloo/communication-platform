"""The core `AppConfig`, and the two bindings its `ready()` is the only cause of.

`core` is plumbing: it holds the bucket sets, the opaque blob field, the log
scrubber and the panel's base classes, and it declares no model at all. What its
`ready()` does is import the two modules whose import *is* their effect — the
deploy checks register themselves on import, and the lockout binds itself to the
login signals on import — so nothing else in the tree references either module and
a lost `ready()` would be silent.
"""

import redis
from django.apps import apps
from django.conf import settings
from django.contrib.auth.signals import user_login_failed
from django.core.checks.registry import registry
from django.test import SimpleTestCase

from core import checks
from core.apps import CoreConfig
from core.lockout import ADMIN, _key

NAME = "signal-probe"


def store():
    return redis.Redis.from_url(settings.REDIS_URL)


class CoreConfigTests(SimpleTestCase):
    def test_the_app_is_configured_under_the_label_the_settings_list_uses(self):
        config = apps.get_app_config("core")

        self.assertIsInstance(config, CoreConfig)
        self.assertEqual(config.name, "core")
        self.assertEqual(config.default_auto_field, "django.db.models.BigAutoField")

    def test_the_app_declares_no_model_and_owns_no_migration(self):
        """A seizure of this backend yields no `core` table, because there is
        none. `core/tests/test_migrations.py` records the apps that do own one."""
        self.assertEqual(list(apps.get_app_config("core").get_models()), [])
        self.assertFalse((settings.BASE_DIR / "core" / "migrations").exists())

    def test_importing_the_package_itself_runs_nothing(self):
        """`core/env.py` is imported by `config/settings/base.py` before Django is
        configured at all. A package `__init__` that touched settings or the app
        registry would make the settings module unimportable."""
        self.assertEqual((settings.BASE_DIR / "core" / "__init__.py").read_text(), "")

    def test_ready_put_every_deploy_check_of_the_module_in_the_registry(self):
        """The checks register themselves when `core.checks` is imported, and
        `ready()` is the only import of it. Without that import `manage.py check
        --deploy` reports nothing and passes."""
        declared = {
            checks.no_foreign_or_telemetry,
            checks.redis_requires_a_password,
            checks.infrastructure_secrets_are_strong,
            checks.ws_origin_allowlist_set,
        }

        self.assertLessEqual(declared, registry.deployment_checks)


class LoginSignalBindingTests(SimpleTestCase):
    """The signals `core.lockout` binds on import, observed through the counter
    they write rather than through the receiver list — a receiver registered twice
    counts one failed sign-in as two, which is a fifth of the whole budget."""

    def setUp(self):
        self.store = store()
        self.addCleanup(self.store.close)
        self.addCleanup(self.store.delete, _key(ADMIN, "fails", NAME))
        self.addCleanup(self.store.delete, _key(ADMIN, "lock", NAME))
        self.store.delete(_key(ADMIN, "fails", NAME), _key(ADMIN, "lock", NAME))

    def test_one_failed_sign_in_is_counted_exactly_once(self):
        user_login_failed.send(
            sender=object, credentials={"username": NAME}, request=None
        )

        self.assertEqual(int(self.store.get(_key(ADMIN, "fails", NAME))), 1)

    def test_a_second_ready_never_binds_a_second_receiver(self):
        """`dispatch_uid` is what makes this hold. `ready()` runs once per
        process today, but an `AppConfig` re-entered — a test that reloads the
        registry, a management command that calls `django.setup()` twice — must
        not double every guess an operator makes."""
        apps.get_app_config("core").ready()

        user_login_failed.send(
            sender=object, credentials={"username": NAME}, request=None
        )

        self.assertEqual(int(self.store.get(_key(ADMIN, "fails", NAME))), 1)
