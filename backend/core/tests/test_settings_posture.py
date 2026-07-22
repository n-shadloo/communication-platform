from django.conf import settings
from django.test import SimpleTestCase, override_settings

from config.settings import prod
from core.checks import no_foreign_or_telemetry, ws_origin_allowlist_set

BANNED_TELEMETRY = {"sentry_sdk", "ddtrace", "newrelic", "elasticapm"}


class BasePostureTests(SimpleTestCase):
    """Posture that must hold in every environment (ARCHITECTURE §A3, §A8, §A11)."""

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

    def test_refresh_tokens_rotate_and_blacklist(self):
        self.assertTrue(settings.SIMPLE_JWT["ROTATE_REFRESH_TOKENS"])
        self.assertTrue(settings.SIMPLE_JWT["BLACKLIST_AFTER_ROTATION"])

    def test_api_authenticates_with_the_device_aware_class(self):
        self.assertEqual(settings.REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"],
                         ["accounts.auth.DeviceJWTAuthentication"])

    def test_datastores_are_localhost_only(self):
        self.assertIn(settings.DATABASES["default"]["HOST"], {"127.0.0.1", "localhost"})
        for location in (settings.CACHES["default"]["LOCATION"],
                         *settings.CHANNEL_LAYERS["default"]["CONFIG"]["hosts"]):
            self.assertRegex(location, r"^redis://(127\.0\.0\.1|localhost):")

    def test_scrub_filter_is_attached_and_access_logging_is_off(self):
        logging = settings.LOGGING

        self.assertIn("scrub", logging["handlers"]["console"]["filters"])
        self.assertEqual(logging["filters"]["scrub"]["()"],
                         "core.logging_filters.ScrubFilter")
        for logger in ("django.request", "django.server"):
            self.assertEqual(logging["loggers"][logger]["level"], "ERROR")

    def test_core_deploy_check_reports_nothing(self):
        self.assertEqual(no_foreign_or_telemetry(None), [])

    def test_ws_origin_check_passes_when_the_allowlist_is_set(self):
        self.assertEqual(ws_origin_allowlist_set(None), [])

    def test_ws_origin_check_fails_on_an_empty_allowlist(self):
        # Empty = allow-any-Origin in the consumer (dev behaviour); prod must set it (§A6).
        with override_settings(ALLOWED_WS_ORIGINS=[]):
            errors = ws_origin_allowlist_set(None)
        self.assertEqual([e.id for e in errors], ["core.E003"])


class ProdPostureTests(SimpleTestCase):
    """`config.settings.prod` is what `check --deploy` runs against (§A10)."""

    def test_debug_is_off(self):
        self.assertFalse(prod.DEBUG)

    def test_transport_is_https_only(self):
        self.assertTrue(prod.SECURE_SSL_REDIRECT)
        self.assertEqual(prod.SECURE_PROXY_SSL_HEADER,
                         ("HTTP_X_FORWARDED_PROTO", "https"))

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
