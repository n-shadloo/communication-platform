"""The voice-rooms `AppConfig`.

Ten lines, and three of them are load-bearing. The label is what this app's one
migration, its admin URLs and every `apps.get_model` call spell; the
`verbose_name` is the word the operator reads at the top of every room page, and
the comment above it records that Django would otherwise derive "Voicerooms",
which is in no language; and the model set is a design statement — a room is a
capability id and an encrypted name, so a second model here would be the
membership table, the roster or the participant history this design forbids.
"""

from django.apps import AppConfig, apps
from django.conf import settings

from voicerooms.apps import VoiceroomsConfig
from voicerooms.models import Room


def test_the_app_is_registered_under_the_label_its_migration_is_keyed_on():
    config = apps.get_app_config("voicerooms")

    assert isinstance(config, VoiceroomsConfig)
    assert (config.name, config.label) == ("voicerooms", "voicerooms")
    assert config.default_auto_field == "django.db.models.BigAutoField"


def test_the_app_is_in_the_installed_list_the_settings_module_holds():
    assert "voicerooms" in settings.INSTALLED_APPS


def test_the_app_names_itself_in_operator_words_rather_than_letting_django_derive_it():
    """Django titles the module name when an app declares no `verbose_name`, and
    "Voicerooms" is what the breadcrumb of every room page would then read."""
    assert str(apps.get_app_config("voicerooms").verbose_name) == "Voice rooms"


def test_the_app_declares_exactly_one_model():
    """A second model here is a membership table, a roster or a participant
    history — none of which this server may hold, and none of which any other
    test would notice on the day it is added."""
    assert list(apps.get_app_config("voicerooms").get_models()) == [Room]


def test_the_config_adds_no_ready_hook():
    """`ready()` is where an app binds signals or starts work at boot. This one
    inherits Django's no-op, so nothing in this app runs outside a request."""
    assert VoiceroomsConfig.ready is AppConfig.ready


def test_importing_the_package_itself_runs_nothing():
    assert (settings.BASE_DIR / "voicerooms" / "__init__.py").read_text() == ""
