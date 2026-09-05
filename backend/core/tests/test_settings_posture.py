import re

from django.conf import settings
from django.core.checks import Tags, run_checks
from django.test import SimpleTestCase, override_settings

from config.settings import prod
from core.checks import no_foreign_or_telemetry

# The band's ceiling on concurrent WebSocket connections: fewer than 50 accounts
# at `MAX_DEVICES_PER_USER` devices each, recorded as A1 in
# `docs/architecture/DESIGN-RECORD.md`. It lives there rather than in a setting,
# because nothing in this process enforces it.
SOCKET_CEILING = 500

# The one site file `ops/nginx/` carries; the per-location assertions below read
# it by name rather than by glob, so a rename fails here instead of passing over
# an empty match.
SITE = "chat.nimashadloo.dev.conf"


def deploy_check_ids():
    """The ids `manage.py check --deploy` would report under the current settings,
    read through the registry so a check that is written but never registered
    for deployment fails here."""
    return {
        message.id
        for message in run_checks(tags=[Tags.security], include_deployment_checks=True)
    }


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


def nginx_locations(conf):
    """Every `location` block of the TLS server block, as {spec: body}.

    Written here rather than pulled from a parser package: the properties below
    are per-location, and `str.count` over the whole file cannot tell a cap in
    one location from a cap in another.
    """
    tls = next(
        body
        for match in re.finditer(r"^server\s*\{", conf, re.M)
        for body in [_block(conf, match.start())]
        if "listen 443" in body
    )
    blocks = {}
    for match in re.finditer(r"^\s*location\s+(?P<spec>[^{#]+?)\s*\{", tls, re.M):
        blocks[match.group("spec")] = _block(tls, match.start())
    return blocks


def _block(text, at):
    """The body of the brace-delimited block whose opening brace follows `at`."""
    start = text.index("{", at)
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : index]
    raise AssertionError("unbalanced braces")


def nginx_size(value):
    """An nginx size — a number with an optional `k` or `m` suffix — as bytes."""
    scale = {"k": 1024, "m": 1024**2}
    if value[-1].lower() in scale:
        return int(value[:-1]) * scale[value[-1].lower()]
    return int(value)


def nginx_seconds(value):
    """An nginx time — a number with an optional `s` suffix — as seconds."""
    return int(value.removesuffix("s"))


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
        # One Redis URL: the rate counters, the lockout, the room presence sets and
        # the gateway's fan-out bus all read `REDIS_URL`.
        self.assertRegex(
            settings.REDIS_URL, r"^redis://(:[^@]+@)?(127\.0\.0\.1|localhost):"
        )

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

    def test_the_edge_writes_no_access_log_and_no_request_line(self):
        """The other half of `--no-access-log`, one layer out.

        nginx sees every request the process sees, one hop earlier, and it has no
        `access_log off` of its own to inherit: the compiled-in default is
        `access_log logs/access.log combined`, and every packaged `nginx.conf`
        sets one in the `http` block that a `server` block inherits unless it
        overrides it. The `combined` format writes `$remote_addr` and `$request`,
        which is the client address and the whole URI — the peer user UUID of the
        key-claim and device routes, the operator-chosen admin path, and the
        bearer capability that downloads an attachment.

        `error_log` carries the same line: an upstream failure is logged at
        `error` level with `client:` and `request:` fields, so a restarting worker
        would write the paths the access log no longer does. `crit` is the level
        above it.
        """
        for conf in (settings.BASE_DIR / "ops" / "nginx").glob("*.conf"):
            body = conf.read_text()
            # Per server block, not per file: a directive in one block does not
            # reach the other, and the plaintext block sees a URI too — whatever
            # path a request named before the redirect sends it on.
            blocks = len(re.findall(r"^server \{", body, re.M))

            self.assertEqual(body.count("access_log off;"), blocks, conf.name)
            self.assertEqual(
                len(re.findall(r"error_log\s+\S+\s+crit;", body)), blocks, conf.name
            )

    def test_every_location_of_the_edge_caps_the_body_it_admits(self):
        """A cap on the server block alone is the cap of whichever location admits
        the most, applied to every location that admits less. The upload route
        needs 70 MiB, so one server-level number would let a 70 MiB body reach the
        admin path — which the application then refuses with `413` after nginx has
        already carried it to loopback. Each location states its own instead, and
        the server-level value is the deny-by-default for a path that matches
        none."""
        conf = (settings.BASE_DIR / "ops" / "nginx" / SITE).read_text()
        locations = nginx_locations(conf)

        self.assertTrue(locations)
        for spec, body in locations.items():
            self.assertIn("client_max_body_size", body, spec)

    def test_the_edge_admits_exactly_what_each_upstream_admits(self):
        """The two caps are one setting in two places. nginx above the application
        would 413 a body the routes accept; nginx below it would carry a body the
        routes refuse. `/api/` takes the largest route class, and the admin claims
        no route at all, so `api.app.route_limits` gives it the fallback class."""
        locations = nginx_locations(
            (settings.BASE_DIR / "ops" / "nginx" / SITE).read_text()
        )
        caps = {
            spec: nginx_size(re.search(r"client_max_body_size\s+(\S+);", body).group(1))
            for spec, body in locations.items()
        }

        self.assertEqual(caps["/api/"], settings.BODY_CAP_BATCH_BYTES)
        self.assertEqual(caps["/admin/"], settings.BODY_CAP_JSON_BYTES)

    def test_the_edge_waits_longer_than_the_deadline_below_it(self):
        """Timeouts nest innermost first. The application answers its own
        `503 unavailable` at its deadline; nginx must still be waiting then, or a
        slow request becomes a `504` with no answer from the application and the
        deadline's envelope never reaches the client. nginx's own default is 60 s,
        which is below the 120 s the upload and batch routes take."""
        locations = nginx_locations(
            (settings.BASE_DIR / "ops" / "nginx" / SITE).read_text()
        )
        waits = {
            spec: nginx_seconds(re.search(r"proxy_read_timeout\s+(\S+);", body).group(1))
            for spec, body in locations.items()
            if "proxy_pass" in body
        }

        self.assertGreater(waits["/api/"], settings.UPLOAD_DEADLINE_SECONDS)
        self.assertGreater(waits["/admin/"], settings.REQUEST_DEADLINE_SECONDS)

    def test_one_layer_owns_the_transport_security_header(self):
        """`add_header` appends; it never replaces. Django's SecurityMiddleware
        emits HSTS on the admin path it serves, and SECURE_HSTS_SECONDS has to stay
        set there because `check --deploy` requires it — so without the hide the
        admin response carries the header twice. nginx is the layer that keeps it,
        because it is the only one that sees every response on this host: the
        proxied ones, the files it serves from disk, and its own 404 and 413.

        The mirror of that rule is the second assertion: a location that adds a
        header of its own drops every inherited one, so it repeats HSTS or it
        serves without it.
        """
        conf = (settings.BASE_DIR / "ops" / "nginx" / SITE).read_text()
        snippet = (
            settings.BASE_DIR / "ops" / "nginx" / "snippets" / "proxy-headers.conf"
        ).read_text()

        self.assertIn("proxy_hide_header Strict-Transport-Security;", snippet)
        self.assertTrue(prod.SECURE_HSTS_SECONDS)
        for spec, body in nginx_locations(conf).items():
            if "proxy_pass" in body:
                self.assertIn("snippets/proxy-headers.conf", body, spec)
            elif "add_header" in body:
                self.assertIn("Strict-Transport-Security", body, spec)

    def test_the_edge_includes_only_snippets_this_repository_ships(self):
        """An `include` that names a file nobody wrote is a site that does not
        load, and the snippet behind this one carries X-Forwarded-Proto — the
        header SECURE_PROXY_SSL_HEADER trusts. An operator inventing it is an
        operator choosing that trust boundary by hand."""
        conf = (settings.BASE_DIR / "ops" / "nginx" / SITE).read_text()

        for included in re.findall(r"include\s+(\S+);", conf):
            self.assertTrue(
                (settings.BASE_DIR / "ops" / "nginx" / included).is_file(), included
            )

    def test_the_three_windows_of_a_stop_nest(self):
        """A deploy is a stop, and three windows have to nest around it: the
        longest request the surface admits, the drain uvicorn takes, and the time
        systemd waits before SIGKILL. Measured on this application with the drain
        below the request: the request was cut and the client read
        `HTTP/1.1 500 Internal Server Error`, so a deploy that caught a slow upload
        reported itself as a fault of the API. With the drain above it the same
        probe completed and read its real status.

        systemd's own `DefaultTimeoutStopSec` is 90 s, so the outermost window is
        stated rather than inherited: an unset value would be below the drain and
        would kill the process in the middle of it.
        """
        unit = (settings.BASE_DIR / "ops" / "systemd" / "chat.service").read_text()
        drain = int(re.search(r"--timeout-graceful-shutdown (\d+)", unit).group(1))
        stop = int(re.search(r"TimeoutStopSec=(\d+)", unit).group(1))

        self.assertGreater(drain, settings.UPLOAD_DEADLINE_SECONDS)
        self.assertGreater(stop, drain)

    def test_the_maintenance_run_is_bounded_rather_than_left_to_a_default(self):
        """systemd will not start a second instance of the unit while one is
        active, so a sweep that never returns holds the timer's every later fire
        behind it. The distribution default would instead kill a large sweep at
        90 s and mark the unit failed. The bound is stated so it is neither."""
        unit = (
            settings.BASE_DIR / "ops" / "systemd" / "chat-maintenance.service"
        ).read_text()

        self.assertIsNotNone(re.search(r"^TimeoutStartSec=\S+$", unit, re.M))

    def test_the_concurrency_limit_leaves_room_for_http_beside_the_sockets(self):
        """uvicorn's `--limit-concurrency` counts *connections*, and a live
        WebSocket is one: both protocols share `server_state.connections`, and the
        HTTP path answers `503` from the length of that shared set. The WebSocket
        handshake never consults it — the upgrade returns before the check — so
        sockets take from the budget and never give it back.

        Measured with the limit at 6: six live sockets, and every HTTP request
        answers uvicorn's own plain-text `503 Service Unavailable`, not even this
        API's envelope. At the band's ceiling of `SOCKET_CEILING` concurrent
        sockets, a limit of 512 would leave twelve connections for every send, ack,
        drain and key claim the deployment makes.

        So the limit carries both: the socket ceiling, plus one keep-alive HTTP
        connection for each of those devices. 500 live sockets cost 47 MB of
        resident set (189.8 MB idle against 237.0 MB), and an idle HTTP connection
        is cheaper than a socket, so the memory stays inside A3's 700 MB ceiling.
        """
        unit = (settings.BASE_DIR / "ops" / "systemd" / "chat.service").read_text()
        limit = int(re.search(r"--limit-concurrency (\d+)", unit).group(1))

        self.assertGreaterEqual(limit, 2 * SOCKET_CEILING)

    def test_the_serving_unit_raises_its_file_descriptor_limit_to_match(self):
        """A connection is a file descriptor, and systemd's own default soft
        `LimitNOFILE` is 1024. Admitting more connections than the process has
        descriptors for moves the failure rather than removing it: the accept fails
        instead of the concurrency check, and it fails without a `503`.

        The budget is the connection limit, plus the sixteen the database pool
        holds, plus the Redis client and its subscription, plus the listening
        socket and stdio.
        """
        unit = (settings.BASE_DIR / "ops" / "systemd" / "chat.service").read_text()
        limit = int(re.search(r"--limit-concurrency (\d+)", unit).group(1))
        descriptors = re.search(r"LimitNOFILE=(\d+)", unit)

        self.assertIsNotNone(descriptors, "the unit sets no LimitNOFILE")
        self.assertGreater(int(descriptors.group(1)), limit)

    def test_the_units_write_only_what_they_must_and_drop_what_they_never_use(self):
        """`ReadWritePaths` is the whole of what a compromised process can change
        on a `ProtectSystem=strict` host. The serving process never writes the
        collected static tree — `collectstatic` is the operator's command and
        nginx serves the result — so a writable `static_root` was a way for a
        compromised process to replace the panel's own JavaScript. The rest are the
        directives a Python service never needs and a hardened unit drops."""
        units = settings.BASE_DIR / "ops" / "systemd"
        serving = (units / "chat.service").read_text()
        maintenance = (units / "chat-maintenance.service").read_text()

        self.assertIn("ReadWritePaths=/srv/chat/backend/media_root\n", serving)
        self.assertNotIn("static_root", serving)
        for unit in (serving, maintenance):
            for directive in (
                "RestrictRealtime=true",
                "RestrictSUIDSGID=true",
                "ProtectClock=true",
                "ProtectHostname=true",
                "SystemCallArchitectures=native",
            ):
                self.assertIn(directive, unit)

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

    def test_no_django_cache_backend_reads_redis(self):
        """Every built-in Django cache backend unpickles what it reads, and Redis
        is a store another process on the host can write to. Nothing in this
        process may turn Redis bytes back into Python objects: the counters, the
        lockout state and the presence sets are read as strings through the redis
        client, and the Django cache framework is left on its process-local
        default that no other software reaches."""
        backend = settings.CACHES["default"]["BACKEND"]

        self.assertNotIn("redis", backend.lower())
        self.assertTrue(backend.endswith("LocMemCache"), backend)

    def test_the_deploy_checks_refuse_a_redis_url_without_a_password(self):
        """Redis listens on loopback of a host shared with other projects. Without
        `requirepass` every local process can flush the rate counters and the
        lockout, inject frames on the fan-out bus, and read the presence sets."""
        with override_settings(REDIS_URL="redis://127.0.0.1:6379/0"):
            failing = deploy_check_ids()
        with override_settings(REDIS_URL="redis://:generated-secret@127.0.0.1:6379/0"):
            passing = deploy_check_ids()

        self.assertIn("core.E004", failing)
        self.assertNotIn("core.E004", passing)

    def test_the_deploy_checks_refuse_a_weak_infrastructure_secret(self):
        """The signing key mints a token for any account, and the LiveKit secret
        mints a join token for any room. Django checks its own SECRET_KEY's
        strength and nothing checked these two, so a short value or the
        development fallback reached production in silence."""
        strong = "s" * 32
        cases = {
            "short signing key": {"JWT_SIGNING_KEY": "s" * 31},
            "the development fallback": {"JWT_SIGNING_KEY": "dev-insecure-jwt-key"},
            "the signing key reused as SECRET_KEY": {
                "JWT_SIGNING_KEY": strong,
                "SECRET_KEY": strong,
            },
            "short LiveKit secret with voice configured": {
                "LIVEKIT_URL": "wss://chat.example",
                "LIVEKIT_API_KEY": "key",
                "LIVEKIT_API_SECRET": "s" * 31,
            },
        }
        for label, overrides in cases.items():
            with self.subTest(label), override_settings(**overrides):
                self.assertIn("core.E005", deploy_check_ids(), label)

        with override_settings(
            JWT_SIGNING_KEY=strong,
            SECRET_KEY="k" * 50,
            LIVEKIT_URL="wss://chat.example",
            LIVEKIT_API_KEY="key",
            LIVEKIT_API_SECRET="l" * 32,
        ):
            self.assertNotIn("core.E005", deploy_check_ids())
        # Voice off: the LiveKit secret is not read at all, so an empty one passes.
        with override_settings(
            JWT_SIGNING_KEY=strong, LIVEKIT_URL="", LIVEKIT_API_SECRET=""
        ):
            self.assertNotIn("core.E005", deploy_check_ids())


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

    def test_the_admin_cookies_carry_the_host_prefix(self):
        """The VPS serves two other projects, on sibling names of the same domain
        for all this configuration knows. A `__Host-` cookie is accepted only over
        HTTPS, without a `Domain`, and with `Path=/`, so a sibling site — or a
        subdomain an attacker controls — cannot set one for the panel and no
        broader cookie of the same name can shadow it."""
        from django.conf import global_settings

        def effective(name):
            return getattr(prod, name, getattr(global_settings, name))

        self.assertEqual(prod.SESSION_COOKIE_NAME, "__Host-sessionid")
        self.assertEqual(prod.CSRF_COOKIE_NAME, "__Host-csrftoken")
        self.assertIsNone(effective("SESSION_COOKIE_DOMAIN"))
        self.assertIsNone(effective("CSRF_COOKIE_DOMAIN"))
        self.assertEqual(effective("SESSION_COOKIE_PATH"), "/")
        self.assertEqual(effective("CSRF_COOKIE_PATH"), "/")

    def test_hsts_is_a_full_year_with_subdomains_and_preload(self):
        self.assertEqual(prod.SECURE_HSTS_SECONDS, 31536000)
        self.assertTrue(prod.SECURE_HSTS_INCLUDE_SUBDOMAINS)
        self.assertTrue(prod.SECURE_HSTS_PRELOAD)

    def test_content_type_and_framing_are_locked_down(self):
        self.assertTrue(prod.SECURE_CONTENT_TYPE_NOSNIFF)
        self.assertEqual(prod.X_FRAME_OPTIONS, "DENY")


# The trees `coverage` omits that are not this project's code: the installed
# toolchain, and the untracked wheel cache of ADR-0012.
NOT_PROJECT_CODE = frozenset({".venv/*", "vendor/*"})
# The project code it omits, and the reason each one is not measured.
UNMEASURED = {
    "*/migrations/*": "generated by makemigrations; the migration suite replays them",
    "*/tests/*": "the suite does not measure itself",
    "manage.py": "a four-line Django entry point",
    "devices/vectors/generate.py": "a developer tool that writes the golden vectors",
}


class TestToolchainPostureTests(SimpleTestCase):
    """How the suite itself is configured to run.

    Two knobs decide what the numbers this run produces mean. The coverage omit
    list decides what the figure is a figure *of* — an omission added quietly is a
    module that stops being measured and never fails a floor. And the Hypothesis
    profile decides whether the property tests explore the same inputs twice: the
    suite runs under `pytest-randomly`, which reseeds the global RNG for every
    test, so an entropy-driven profile would give the gate's two orderings two
    different sets of examples and a failure nobody could reproduce.
    """

    def coverage_config(self):
        import tomllib

        text = (settings.BASE_DIR / "pyproject.toml").read_text()
        return tomllib.loads(text)["tool"]["coverage"]

    def test_coverage_measures_branches_over_the_whole_repository(self):
        """`source` is the repository rather than a list of apps, so a new app is
        measured the day it is created and not the day somebody remembers it."""
        run = self.coverage_config()["run"]

        self.assertIs(run["branch"], True)
        self.assertEqual(run["source"], ["."])

    def test_coverage_omits_exactly_the_four_project_paths_that_were_decided(self):
        """Anything else in this list is code that silently stops being counted."""
        omitted = set(self.coverage_config()["run"]["omit"])

        self.assertEqual(omitted - NOT_PROJECT_CODE, set(UNMEASURED))
        self.assertEqual(omitted & NOT_PROJECT_CODE, NOT_PROJECT_CODE)

    def test_every_omitted_file_still_exists(self):
        """An omit for a path that moved excludes nothing and reads as though it
        still does."""
        for name in UNMEASURED:
            if "*" in name:
                continue
            with self.subTest(name=name):
                self.assertTrue((settings.BASE_DIR / name).exists(), name)

    def test_the_property_tests_run_under_the_derandomised_profile(self):
        """`conftest.py` registers it and loads it. Entropy here would mean a
        property that fails in one ordering and passes in the other, with the
        failing example behind a seed nobody recorded."""
        from hypothesis import settings as hypothesis_settings

        profile = hypothesis_settings.default

        self.assertIs(profile.derandomize, True)
        self.assertIsNone(profile.database)
        self.assertIsNone(profile.deadline)

    def test_the_example_budget_is_fixed_and_bounded(self):
        """This is a suite, not a fuzzing campaign: the gate has to finish, and a
        budget nobody can read from the code is a runtime nobody can predict."""
        from hypothesis import settings as hypothesis_settings

        self.assertEqual(hypothesis_settings.default.max_examples, 200)

    def test_no_hypothesis_example_database_is_written_into_the_tree(self):
        """`database=None` is what keeps the example database off disk.

        Without it a property that failed once replays its failing example from a
        directory in the working tree, so a run's result depends on an earlier
        run's — and the derandomised profile above would no longer be the whole
        story. Hypothesis writes its own constant and unicode caches under
        `.hypothesis/` whatever the database setting is, and ships a `.gitignore`
        of its own that keeps them out of git; that is the part the repository
        tolerates.
        """
        tree = settings.BASE_DIR / ".hypothesis"

        self.assertFalse((tree / "examples").exists())
        if tree.exists():
            self.assertIn("\n*", (tree / ".gitignore").read_text())
