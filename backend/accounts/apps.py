from django.apps import AppConfig
from django.utils.translation import gettext_lazy as _


class AccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "accounts"
    # Declared, never derived: Django titles the label when an app omits
    # this, and the breadcrumb of every page of this app is what shows it.
    verbose_name = _("Accounts")
