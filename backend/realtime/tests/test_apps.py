"""The realtime `AppConfig`, and the design statement it carries.

Four lines of configuration, and what matters about them is what is absent. The
app that carries every live frame declares no model at all: presence, signals and
room text are volatile by construction, so there is no table for them to be
written into and no migration that could add one without this file noticing. The
label is what `config/settings/base.py` lists and what every `get_app_config`
call in the project spells.
"""

from django.apps import AppConfig, apps
from django.conf import settings

from realtime.apps import RealtimeConfig


def test_the_app_is_configured_under_the_label_the_settings_list_uses():
    config = apps.get_app_config("realtime")

    assert isinstance(config, RealtimeConfig)
    assert config.name == "realtime"
    assert config.label == "realtime"
    assert config.default_auto_field == "django.db.models.BigAutoField"


def test_the_app_is_installed():
    assert "realtime" in settings.INSTALLED_APPS


def test_the_app_declares_no_model_and_owns_no_migration():
    """A model here would be a table for volatile traffic, which is the whole of
    what this app refuses to keep. `voicerooms` owns the one room row; the live
    membership of that room is a Redis set, and the socket state is memory."""
    assert list(apps.get_app_config("realtime").get_models()) == []
    assert not (settings.BASE_DIR / "realtime" / "migrations").exists()


def test_the_config_adds_no_ready_hook():
    """`ready()` is where an app starts work at boot. The bus builds its
    subscriber on first use and keys it by the running loop, so a `ready()` that
    opened one would bind it to whichever loop imported Django — which in a
    worker is not the loop that serves any socket."""
    assert RealtimeConfig.ready is AppConfig.ready


def test_importing_the_package_itself_runs_nothing():
    """`realtime.bus` is imported by `accounts`, `devices` and both admin sites,
    which run before any loop exists. A package `__init__` that touched the loop
    or the settings would break the import for all of them."""
    assert (settings.BASE_DIR / "realtime" / "__init__.py").read_text() == ""
