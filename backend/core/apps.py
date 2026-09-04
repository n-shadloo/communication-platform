from django.apps import AppConfig


class CoreConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "core"

    def ready(self):
        from . import (
            checks,  # noqa: F401  (registers the deploy checks)
            lockout,  # noqa: F401  (binds the admin login-failure signals)
        )
