from django.core.checks import Error, register, Tags

@register(Tags.security, deploy=True)
def no_foreign_or_telemetry(app_configs, **kwargs):
    from django.conf import settings
    errors = []
    banned = {"sentry_sdk", "ddtrace", "newrelic", "elasticapm"}
    installed = {a.split(".")[0] for a in settings.INSTALLED_APPS}
    for b in banned & installed:
        errors.append(Error(f"Telemetry/error-reporting app '{b}' is banned (§1A.1).",
                            id="core.E001"))
    if getattr(settings, "EMAIL_BACKEND", "").endswith("smtp.EmailBackend"):
        errors.append(Error("SMTP email backend set; this system sends no email (§1A.1).",
                            id="core.E002"))
    return errors
