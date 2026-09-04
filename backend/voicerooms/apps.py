from django.apps import AppConfig
from django.utils.translation import gettext_lazy as _


class VoiceroomsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "voicerooms"
    # Declared, never derived: Django titles the label when an app omits
    # this, and the breadcrumb of every page of this app is what shows it.
    verbose_name = _("Voice rooms")
