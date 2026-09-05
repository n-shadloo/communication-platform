"""`config/asgi.py`: what the server is handed, and the order it is built in.

ADR-0003 puts one process behind one port: FastAPI is the root application for
every scope and the Django application answers `ADMIN_PATH` behind it. The
topology of that composition is held by `core/tests/test_route_table.py` and the
dispatcher itself by `api/tests/test_app.py`. What is left here is the module —
the two objects it exports, the middleware stack it wraps around them, and the
import order that makes it importable at all.

The boot tests run a fresh interpreter. Inside this one the app registry is
already populated and the settings module already chosen, so nothing that happens
here could observe either going wrong; a subprocess is the only place the first
import of `config.asgi` still lies ahead.
"""

import json
import os
import subprocess
import sys

from django.conf import settings
from django.core.handlers.asgi import ASGIHandler
from fastapi import FastAPI

from api.middleware import (
    BodyCap,
    RequestDeadline,
    ResponseHeaders,
    ThreadSensitive,
    TrustedHost,
)
from config.asgi import api_application, application, django_asgi_app

# The stack `api.app.wrap` builds, outermost first. The order is the decision:
# the host check refuses before a body is read, the deadline starts before the
# body cap counts against it, and the ORM's thread-sensitive context is innermost
# so that it wraps only what the routes do.
STACK = [TrustedHost, RequestDeadline, BodyCap, ResponseHeaders, ThreadSensitive]

# The two variables `base` requires and `dev` supplies a fallback for.
SECRETS = ("DJANGO_SECRET_KEY", "JWT_SIGNING_KEY")

# What the subprocess reports back. Everything a fresh import decides.
PROBE = """
import json, os
import config.asgi as asgi
from django.apps import apps
from django.conf import settings
print(json.dumps({
    "settings_module": os.environ["DJANGO_SETTINGS_MODULE"],
    "apps_ready": apps.ready,
    "debug": settings.DEBUG,
    "root": type(asgi.api_application).__name__,
    "outermost": type(asgi.application).__name__,
    "openapi_url": asgi.api_application.openapi_url,
    "docs_url": asgi.api_application.docs_url,
    "session_cookie": settings.SESSION_COOKIE_NAME,
    "routes": len(asgi.api_application.routes),
}))
"""


def run_boot(without=(), **environment):
    """Import `config.asgi` in an interpreter of its own.

    `DJANGO_SETTINGS_MODULE` is always cleared: the module's own `setdefault` is
    what has to choose one, and this process inherited a choice from `pytest.ini`.
    `without` clears more of the inherited environment, which is how a variable
    can be absent rather than empty — the two are different to `env()`, and only
    the absent one reaches a `setdefault`.
    """
    child = {key: value for key, value in os.environ.items()}
    for key in ("DJANGO_SETTINGS_MODULE", *without):
        child.pop(key, None)
    child["PYTHONPATH"] = str(settings.BASE_DIR)
    child.update(environment)
    return subprocess.run(
        [sys.executable, "-c", PROBE],
        cwd=settings.BASE_DIR,
        env=child,
        capture_output=True,
        text=True,
        timeout=120,
    )


def boot(without=(), **environment):
    """A boot that has to succeed, and what it reported."""
    finished = run_boot(without, **environment)

    assert finished.returncode == 0, finished.stderr[-2000:]
    return json.loads(finished.stdout)


class TestTheExportedObjects:
    def test_the_fastapi_application_is_the_root_of_every_scope(self):
        """Not a dispatcher over two applications, and not a Django project with
        an API mounted inside it: one FastAPI object receives every scope, and the
        Django application is reached through the router's `default` behind it."""
        assert isinstance(api_application, FastAPI)
        assert isinstance(django_asgi_app, ASGIHandler)
        assert api_application.router.default.__module__ == "api.app"

    def test_the_served_application_is_the_middleware_stack_over_that_root(self):
        """`application` is what uvicorn runs and what the suite drives, and it is
        the FastAPI object with five layers around it. Handing the server
        `api_application` instead would drop every one of them and nothing would
        report it: the routes would still answer."""
        layer, chain = application, []
        while not isinstance(layer, FastAPI):
            chain.append(type(layer))
            layer = layer.app

        assert chain == STACK
        assert layer is api_application

    def test_the_host_check_is_built_from_the_configured_allowlist(self):
        """The outermost layer, and the one whose configuration is a list that
        defaults to empty. It reads `ALLOWED_HOSTS` at composition time, so a host
        added to the environment after the process started changes nothing."""
        assert application.allowed == {host.lower() for host in settings.ALLOWED_HOSTS}
        assert application.allow_any is False


class TestTheFirstImport:
    def test_the_app_registry_is_populated_before_any_model_is_imported(self):
        """The import order ADR-0003 calls load-bearing, proved where it can still
        fail. Every import below `get_asgi_application()` reaches a Django model
        through a router, so one moved above it would raise `AppRegistryNotReady`
        on the first import in a fresh interpreter — which is the server's
        start-up, and no test in this process would ever see it."""
        booted = boot()

        assert booted["apps_ready"] is True
        assert booted["root"] == "FastAPI"
        assert booted["outermost"] == "TrustedHost"
        assert booted["routes"] > 0

    def test_the_development_settings_are_the_default_nobody_has_to_set(self):
        """`manage.py` and the suite both name a settings module. uvicorn does not:
        the unit passes `config.asgi:application` and the environment file chooses
        the settings, and this is the fallback when it does not."""
        booted = boot()

        assert booted["settings_module"] == "config.settings.dev"
        assert booted["debug"] is True

    def test_a_chosen_settings_module_is_never_overridden(self, tmp_path):
        """`setdefault`, not an assignment. The deployment sets
        `DJANGO_SETTINGS_MODULE=config.settings.prod` in its environment file, and
        an assignment here would put every production process back on the
        development settings — DEBUG on, the schema published, the cookies without
        their `__Host-` prefix."""
        booted = boot(
            DJANGO_SETTINGS_MODULE="config.settings.prod",
            DJANGO_SECRET_KEY="chosen-secret-for-this-boot",
            JWT_SIGNING_KEY="chosen-signing-key-for-this-boot",
            ATTACHMENTS_ROOT=str(tmp_path),
        )

        assert booted["settings_module"] == "config.settings.prod"
        assert booted["debug"] is False
        assert booted["session_cookie"] == "__Host-sessionid"

    def test_the_schema_and_its_documentation_are_not_registered_in_production(
        self, tmp_path
    ):
        """ADR-0008 keeps them to development. `core/tests/test_route_table.py`
        proves the routes are absent from an application composed under
        `DEBUG=False`; this proves that a process booted the way the deployment
        boots one is that application."""
        booted = boot(
            DJANGO_SETTINGS_MODULE="config.settings.prod",
            DJANGO_SECRET_KEY="chosen-secret-for-this-boot",
            JWT_SIGNING_KEY="chosen-signing-key-for-this-boot",
            ATTACHMENTS_ROOT=str(tmp_path),
        )

        assert booted["openapi_url"] is None
        assert booted["docs_url"] is None

    def test_the_development_settings_supply_the_two_secrets_the_base_requires(self):
        """`dev.py` sets both before its star import, and the order is what makes
        it work: `base` reads them at import time, so a `setdefault` written below
        the import would leave a developer with `ImproperlyConfigured` and a
        `.env` they were told they did not need."""
        booted = boot(without=SECRETS)

        assert booted["settings_module"] == "config.settings.dev"
        assert booted["debug"] is True

    def test_the_production_settings_supply_neither(self, tmp_path):
        """The other half of the same decision: no insecure fallback exists in
        production, so a host that never set the signing key fails to boot rather
        than minting tokens under a key that is in the repository."""
        finished = run_boot(
            without=SECRETS,
            DJANGO_SETTINGS_MODULE="config.settings.prod",
            ATTACHMENTS_ROOT=str(tmp_path),
        )

        assert finished.returncode != 0
        assert "DJANGO_SECRET_KEY" in finished.stderr
