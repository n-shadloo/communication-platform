"""The app declaration itself.

The label is what this app's migration, its `get_model` calls and its admin URLs
are keyed on, and the `verbose_name` is the word at the top of every attachments
page of the panel.
"""

from django.apps import apps

from attachments.apps import AttachmentsConfig


def test_the_app_is_registered_under_the_label_its_migrations_are_keyed_on():
    config = apps.get_app_config("attachments")

    assert isinstance(config, AttachmentsConfig)
    assert (config.name, config.label) == ("attachments", "attachments")


def test_the_app_names_itself_in_operator_words_rather_than_letting_django_derive_it():
    """Django titles the module name when an app declares no `verbose_name`, so
    the breadcrumb would read the label back at the person using it."""
    assert str(apps.get_app_config("attachments").verbose_name) == "Attachments"


def test_the_app_holds_exactly_the_one_model_the_rest_of_the_system_names():
    """A second model here would be a table the panel audit, the seizure guard and
    the manifest suite have never been shown."""
    names = {
        model._meta.model_name
        for model in apps.get_app_config("attachments").get_models()
    }

    assert names == {"attachment"}
