import re

from django.conf import settings
from django.test import SimpleTestCase, override_settings

from config.settings import prod
from core.checks import no_foreign_or_telemetry, ws_origin_allowlist_set

BANNED_TELEMETRY = {"sentry_sdk", "ddtrace", "newrelic", "elasticapm"}

# The modules that read the environment. Every other module reads `settings`.
CONFIGURED_BY = ("config/settings/base.py", "config/settings/dev.py", "config/urls.py")
READS_ENV = re.compile(r"\benv(?:_bool|_int|_list)?\(\s*[\"']([A-Z][A-Z0-9_]*)[\"']")
DECLARES = re.compile(r"^([A-Z][A-Z0-9_]*)=", re.M)
DOCUMENTED = re.compile(r"^\| `([A-Z][A-Z0-9_]*)` \|", re.M)

# Variables the example carries that no Python module reads, each with the process
# that does read it. Nothing else may be in the file.
READ_OUTSIDE_PYTHON = {
    "DJANGO_SETTINGS_MODULE": "django, to find the settings module at all",
    "WEB_CONCURRENCY": "the systemd unit, as uvicorn's --workers argument",
    "TURN_REALM": "ops/coturn/turnserver.conf",
    "TURN_STATIC_AUTH_SECRET": "ops/coturn/turnserver.conf",
}


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
        """There is no `ASGI_APPLICATION` to assert against: that setting is read
        by Channels, which is gone. uvicorn is told the application on its command
        line, and the unit test below is what pins it."""
        self.assertIsNone(settings.WSGI_APPLICATION)
        self.assertFalse(hasattr(settings, "ASGI_APPLICATION"))
        self.assertFalse(hasattr(settings, "CHANNEL_LAYERS"))

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
        is short enough to pin rather than to spot-check.

        The order is pinned with the list because one pair of it is load-bearing:
        `unfold` before `django.contrib.admin`. Reversed, the admin's `ready()` runs
        autodiscover first and unfold then replaces the site those registrations
        landed on, so the panel lists nothing and `manage.py check` still passes.
        """
        self.assertEqual(
            settings.INSTALLED_APPS,
            [
                "unfold",
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
        self.assertLess(
            settings.INSTALLED_APPS.index("unfold"),
            settings.INSTALLED_APPS.index("django.contrib.admin"),
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
        # One Redis URL now, not two: the cache, the rate counters, the room
        # presence sets and the gateway's fan-out bus all read `REDIS_URL`.
        for location in (settings.CACHES["default"]["LOCATION"], settings.REDIS_URL):
            self.assertRegex(location, r"^redis://(127\.0\.0\.1|localhost):")

    def test_scrub_filter_is_attached_and_access_logging_is_off(self):
        logging = settings.LOGGING

        self.assertIn("scrub", logging["handlers"]["console"]["filters"])
        self.assertEqual(
            logging["filters"]["scrub"]["()"], "core.logging_filters.ScrubFilter"
        )
        for logger in ("django.request", "django.server"):
            self.assertEqual(logging["loggers"][logger]["level"], "ERROR")

    def test_every_library_that_can_log_an_identifier_is_claimed(self):
        """Each of these writes a device id, a request path or a ciphertext blob at
        its own default level, and each is claimed here so it goes through the
        console handler — and therefore through ScrubFilter — instead of through a
        stream of its own. `push_response` is the one that matters most: redis-py
        installs a `StreamHandler` to stdout for it the first time a `PubSub` is
        built, unless the logger already exists."""
        loggers = settings.LOGGING["loggers"]

        for name in (
            "uvicorn",
            "uvicorn.error",
            "uvicorn.access",
            "websockets",
            "push_response",
        ):
            self.assertEqual(loggers[name]["handlers"], ["console"], name)
            self.assertEqual(loggers[name]["level"], "WARNING", name)
            self.assertFalse(loggers[name]["propagate"], name)

    def test_the_asgi_unit_runs_uvicorn_with_the_hardened_flags(self):
        """The flags of ADR-0014, read from the unit that actually runs.

        `--no-access-log` is the load-bearing one: uvicorn writes a request line
        for every request, and a request path in the journal is the conversation
        graph the schema refuses to hold. The forwarded-header pin is what makes
        the anonymous rate limit mean anything, and the pinned loop, HTTP and
        WebSocket implementations are what make the process fail loudly on a
        missing wheel rather than fall back to a pure-Python one.
        """
        unit = (settings.BASE_DIR / "ops" / "systemd" / "chat.service").read_text()

        self.assertIn("/uvicorn", unit)
        for flag in (
            "--no-access-log",
            "--proxy-headers",
            "--forwarded-allow-ips 127.0.0.1",
            "--loop uvloop",
            "--http httptools",
            "--ws websockets-sansio",
            "--workers ${WEB_CONCURRENCY}",
            "--limit-concurrency",
            "--timeout-graceful-shutdown",
        ):
            self.assertIn(flag, unit)

    def test_the_example_environment_lists_every_variable_the_code_reads(self):
        """An operator fills in `.env.example` and expects a working deployment. A
        variable the code reads and the example omits is a default nobody chose."""
        read = set()
        for name in CONFIGURED_BY:
            read |= set(READS_ENV.findall((settings.BASE_DIR / name).read_text()))
        declared = set(DECLARES.findall((settings.BASE_DIR / ".env.example").read_text()))

        self.assertEqual(read - declared, set())

    def test_the_example_environment_lists_nothing_the_code_ignores(self):
        """A variable in the example that nothing reads is a setting an operator
        believes they configured. The four the file carries for another process are
        recorded above with the process that reads each one."""
        read = set()
        for name in CONFIGURED_BY:
            read |= set(READS_ENV.findall((settings.BASE_DIR / name).read_text()))
        declared = set(DECLARES.findall((settings.BASE_DIR / ".env.example").read_text()))

        self.assertEqual(declared - read, set(READ_OUTSIDE_PYTHON))

    def test_the_configuration_table_of_the_readme_matches_the_code(self):
        """`backend/README.md` is where the operator reads what a variable does and
        what it defaults to. A row that no code reads describes a knob that does
        nothing; a variable with no row is one nobody can find."""
        documented = set(
            DOCUMENTED.findall((settings.BASE_DIR / "README.md").read_text())
        )
        read = set()
        for name in CONFIGURED_BY:
            read |= set(READS_ENV.findall((settings.BASE_DIR / name).read_text()))

        # `WEB_CONCURRENCY` is read by the systemd unit rather than by Python, and
        # the operator sets it in the same file, so the table carries it too.
        self.assertEqual(documented, read | {"WEB_CONCURRENCY"})

    def test_the_worker_count_has_a_documented_default(self):
        """`--workers ${WEB_CONCURRENCY}` is an empty argument if the operator's
        environment file does not set it, and uvicorn then fails to start."""
        example = (settings.BASE_DIR / ".env.example").read_text()

        self.assertIn("WEB_CONCURRENCY=1", example)

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
