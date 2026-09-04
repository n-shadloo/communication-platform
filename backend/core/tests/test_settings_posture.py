from django.conf import settings
from django.test import SimpleTestCase, override_settings

from config.settings import prod
from core.checks import no_foreign_or_telemetry, ws_origin_allowlist_set

BANNED_TELEMETRY = {"sentry_sdk", "ddtrace", "newrelic", "elasticapm"}


class BasePostureTests(SimpleTestCase):
    """Posture that must hold in every environment."""

    def test_argon2id_is_the_first_password_hasher(self):
        self.assertTrue(settings.PASSWORD_HASHERS[0].endswith("Argon2PasswordHasher"))

    def test_no_email_is_ever_sent(self):
        self.assertFalse(settings.EMAIL_BACKEND.endswith("smtp.EmailBackend"))

    def test_no_telemetry_or_error_reporting_app_is_installed(self):
        installed = {app.split(".")[0] for app in settings.INSTALLED_APPS}
        self.assertEqual(BANNED_TELEMETRY & installed, set())

    def test_deployment_is_asgi_only(self):
        self.assertIsNone(settings.WSGI_APPLICATION)
        self.assertEqual(settings.ASGI_APPLICATION, "config.asgi.application")

    def test_no_token_application_is_installed(self):
        """A token table is a per-device login record at rest. Revocation lives in
        two counters on the device row, so nothing keeps one."""
        self.assertFalse(
            any("simplejwt" in app for app in settings.INSTALLED_APPS),
            settings.INSTALLED_APPS,
        )
        self.assertFalse(hasattr(settings, "SIMPLE_JWT"))

    def test_tokens_are_signed_with_a_pinned_symmetric_algorithm(self):
        self.assertEqual(settings.JWT_ALGORITHM, "HS256")
        self.assertTrue(settings.JWT_SIGNING_KEY)
        self.assertNotEqual(settings.JWT_SIGNING_KEY, settings.SECRET_KEY)

    def test_every_served_route_declares_a_requirement_of_its_own(self):
        """FastAPI has no project-wide permission default, so closed-by-default is
        a per-route declaration and `core/tests/test_route_table.py` is the gate
        that proves each one carries it. This asserts the gate covers the whole
        table rather than a subset of it."""
        from core.tests import test_route_table

        served = set(test_route_table.served())

        self.assertEqual(served, set(test_route_table.EXPECTED))
        self.assertTrue(served)
        for route, (requirement, _scope) in test_route_table.EXPECTED.items():
            self.assertIn(requirement, test_route_table.REQUIREMENTS, route)

    def test_the_installed_applications_are_exactly_the_declared_set(self):
        """One HTTP surface, one set of defaults. A second API framework here is a
        block of defaults that no code reads and every reader trusts, and the list
        is short enough to pin rather than to spot-check."""
        self.assertEqual(
            settings.INSTALLED_APPS,
            [
                "django.contrib.admin",
                "django.contrib.auth",
                "django.contrib.contenttypes",
                "django.contrib.sessions",
                "django.contrib.messages",
                "django.contrib.staticfiles",
                "core",
                "accounts",
                "devices",
                "vault",
                "messaging",
                "attachments",
                "voicerooms",
                "realtime",
            ],
        )
        self.assertFalse(hasattr(settings, "REST_FRAMEWORK"))

    def test_the_orm_holds_no_persistent_connection_and_takes_the_pool(self):
        """Nothing fires Django's request signals in this process, so a persistent
        connection would never be reaped or health-checked. The pool is what
        removes the setup cost that CONN_MAX_AGE=0 would otherwise pay."""
        default = settings.DATABASES["default"]

        self.assertEqual(default["CONN_MAX_AGE"], 0)
        self.assertIn("pool", default["OPTIONS"])
        self.assertGreaterEqual(default["OPTIONS"]["pool"]["max_size"], 1)

    def test_datastores_are_localhost_only(self):
        self.assertIn(settings.DATABASES["default"]["HOST"], {"127.0.0.1", "localhost"})
        for location in (
            settings.CACHES["default"]["LOCATION"],
            *settings.CHANNEL_LAYERS["default"]["CONFIG"]["hosts"],
        ):
            self.assertRegex(location, r"^redis://(127\.0\.0\.1|localhost):")

    def test_scrub_filter_is_attached_and_access_logging_is_off(self):
        logging = settings.LOGGING

        self.assertIn("scrub", logging["handlers"]["console"]["filters"])
        self.assertEqual(
            logging["filters"]["scrub"]["()"], "core.logging_filters.ScrubFilter"
        )
        for logger in ("django.request", "django.server"):
            self.assertEqual(logging["loggers"][logger]["level"], "ERROR")

    def test_the_asgi_unit_disables_daphnes_own_access_log(self):
        """The Django half of access logging is off above, but daphne keeps its own:
        it writes an HTTP access log to stdout whenever verbosity is 1 or more (the
        default) and writes to that stream directly, never through Django's LOGGING,
        so ScrubFilter cannot reach it. Without the flag every request path reaches
        the journal, user UUIDs in the peer-key routes included."""
        unit = (settings.BASE_DIR / "ops" / "systemd" / "chat.service").read_text()

        self.assertIn("--access-log /dev/null", unit)

    def test_core_deploy_check_reports_nothing(self):
        self.assertEqual(no_foreign_or_telemetry(None), [])

    def test_ws_origin_check_passes_when_the_allowlist_is_set(self):
        self.assertEqual(ws_origin_allowlist_set(None), [])

    def test_ws_origin_check_fails_on_an_empty_allowlist(self):
        # Empty means allow-any-Origin in the consumer (dev behaviour); prod must set it.
        with override_settings(ALLOWED_WS_ORIGINS=[]):
            errors = ws_origin_allowlist_set(None)
        self.assertEqual([e.id for e in errors], ["core.E003"])


class ProdPostureTests(SimpleTestCase):
    """`config.settings.prod` is what `check --deploy` runs against."""

    def test_debug_is_off(self):
        self.assertFalse(prod.DEBUG)

    def test_transport_is_https_only(self):
        self.assertTrue(prod.SECURE_SSL_REDIRECT)
        self.assertEqual(
            prod.SECURE_PROXY_SSL_HEADER, ("HTTP_X_FORWARDED_PROTO", "https")
        )

    def test_cookies_are_secure(self):
        self.assertTrue(prod.SESSION_COOKIE_SECURE)
        self.assertTrue(prod.CSRF_COOKIE_SECURE)
        self.assertTrue(prod.SESSION_COOKIE_HTTPONLY)
        self.assertEqual(prod.SESSION_COOKIE_SAMESITE, "Strict")
        self.assertEqual(prod.CSRF_COOKIE_SAMESITE, "Strict")

    def test_hsts_is_a_full_year_with_subdomains_and_preload(self):
        self.assertEqual(prod.SECURE_HSTS_SECONDS, 31536000)
        self.assertTrue(prod.SECURE_HSTS_INCLUDE_SUBDOMAINS)
        self.assertTrue(prod.SECURE_HSTS_PRELOAD)

    def test_content_type_and_framing_are_locked_down(self):
        self.assertTrue(prod.SECURE_CONTENT_TYPE_NOSNIFF)
        self.assertEqual(prod.X_FRAME_OPTIONS, "DENY")
