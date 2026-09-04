"""The app declaration itself.

Small, and load-bearing twice over: the label is what every migration and every
`get_model` call of this app is keyed on, and the model set is what the seizure
guard, the manifest suite and the at-rest dump have all been shown. A second
model here would be a table none of them has ever seen.
"""

from django.apps import apps

from messaging.apps import MessagingConfig
from messaging.models import QueuedEnvelope


def test_the_app_is_registered_under_the_label_its_migrations_are_keyed_on():
    config = apps.get_app_config("messaging")

    assert isinstance(config, MessagingConfig)
    assert (config.name, config.label) == ("messaging", "messaging")


def test_the_app_holds_exactly_the_one_model_the_rest_of_the_system_names():
    names = {
        model._meta.model_name for model in apps.get_app_config("messaging").get_models()
    }

    assert names == {"queuedenvelope"}


def test_the_auto_field_default_never_reaches_a_table_here():
    """The config declares one, as every app of this project does, but the one
    model names its own primary key — so no implicit `bigint` id column exists to
    order rows of different mailboxes against each other in a dump."""
    config = apps.get_app_config("messaging")

    assert config.default_auto_field == "django.db.models.BigAutoField"
    assert QueuedEnvelope._meta.pk.name == "id"
    assert QueuedEnvelope._meta.pk.get_internal_type() == "UUIDField"
