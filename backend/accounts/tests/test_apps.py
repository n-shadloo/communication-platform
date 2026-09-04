"""The app declaration itself.

Small, and load-bearing twice over: the label is what every migration, every
`get_model` call and every admin URL of this app is keyed on, and the
`verbose_name` is what the operator reads at the top of every accounts page.
"""

from django.apps import apps

from accounts.apps import AccountsConfig


def test_the_app_is_registered_under_the_label_its_migrations_are_keyed_on():
    config = apps.get_app_config("accounts")

    assert isinstance(config, AccountsConfig)
    assert (config.name, config.label) == ("accounts", "accounts")


def test_the_app_names_itself_in_operator_words_rather_than_letting_django_derive_it():
    """Django titles the module name when an app declares no `verbose_name`, so
    the breadcrumb would read the label back at the person using it."""
    assert str(apps.get_app_config("accounts").verbose_name) == "Accounts"


def test_the_app_holds_exactly_the_two_models_the_rest_of_the_system_names():
    """A third model here would be a table the panel audit, the seizure guard and
    the manifest suite have never been shown."""
    names = {
        model._meta.model_name for model in apps.get_app_config("accounts").get_models()
    }

    assert names == {"user", "profileblob"}
