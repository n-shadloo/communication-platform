from django.core.checks import Error, Tags, register


@register(Tags.security, deploy=True)
def no_foreign_or_telemetry(app_configs, **kwargs):
    from django.conf import settings

    errors = []
    banned = {"sentry_sdk", "ddtrace", "newrelic", "elasticapm"}
    installed = {a.split(".")[0] for a in settings.INSTALLED_APPS}
    for b in banned & installed:
        errors.append(
            Error(f"Telemetry/error-reporting app '{b}' is banned.", id="core.E001")
        )
    if getattr(settings, "EMAIL_BACKEND", "").endswith("smtp.EmailBackend"):
        errors.append(
            Error("SMTP email backend set; this system sends no email.", id="core.E002")
        )
    return errors


@register(Tags.security, deploy=True)
def redis_requires_a_password(app_configs, **kwargs):
    from urllib.parse import urlsplit

    from django.conf import settings

    # Redis listens on loopback of a host shared with other projects, and loopback
    # is reachable by every local process. Without `requirepass` any of them can
    # flush the rate counters and the lockout, publish frames on the fan-out bus
    # and read the presence sets. ADR-0018.
    if urlsplit(settings.REDIS_URL).password:
        return []
    return [
        Error(
            "REDIS_URL carries no password. Set `requirepass` in the Redis "
            "configuration and carry it as redis://:<password>@127.0.0.1:6379/0.",
            id="core.E004",
        )
    ]


@register(Tags.security, deploy=True)
def ws_origin_allowlist_set(app_configs, **kwargs):
    from django.conf import settings

    # The consumer treats an empty allowlist as allow-any-Origin, a dev convenience
    # that must never reach production, where it would disable the browser CSWSH
    # defense. dev.py defaults the list, so only a prod env can trip this.
    if settings.ALLOWED_WS_ORIGINS:
        return []
    return [
        Error(
            "ALLOWED_WS_ORIGINS is empty: an empty allowlist accepts any "
            "WebSocket Origin. Set the real origin(s) in the environment.",
            id="core.E003",
        )
    ]
