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

@register(Tags.security, deploy=True)
def ws_origin_allowlist_set(app_configs, **kwargs):
    from django.conf import settings
    # The consumer treats an empty allowlist as allow-any-Origin — a dev convenience
    # that must never reach production, where it would disable the browser CSWSH
    # defense (§A6). dev.py defaults the list, so only a prod env can trip this.
    if settings.ALLOWED_WS_ORIGINS:
        return []
    return [Error("ALLOWED_WS_ORIGINS is empty: an empty allowlist accepts any "
                  "WebSocket Origin. Set the real origin(s) in the environment (§A6).",
                  id="core.E003")]
