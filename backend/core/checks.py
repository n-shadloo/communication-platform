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
    # and read the presence sets. ADR-0018. A development machine runs Redis
    # without a password by design, and `DEBUG` is what names one; the settings
    # a deployment runs set it off, and `security.W018` says so when they do not.
    if settings.DEBUG or urlsplit(settings.REDIS_URL).password:
        return []
    return [
        Error(
            "REDIS_URL carries no password. Set `requirepass` in the Redis "
            "configuration and carry it as redis://:<password>@127.0.0.1:6379/0.",
            id="core.E004",
        )
    ]


@register(Tags.security, deploy=True)
def infrastructure_secrets_are_strong(app_configs, **kwargs):
    from django.conf import settings

    # Django checks the strength of SECRET_KEY itself (security.W009). These two
    # are the other secrets this process signs with: the signing key mints a
    # token for any account, and the LiveKit secret a join token for any room.
    # HS256 wants a key of at least 256 bits, and nothing else refused a short
    # value, the development fallback, or a key shared with SECRET_KEY.
    weak = []
    key = settings.JWT_SIGNING_KEY
    if len(key) < 32 or key == "dev-insecure-jwt-key" or key == settings.SECRET_KEY:
        weak.append("JWT_SIGNING_KEY")
    if settings.LIVEKIT_URL and len(settings.LIVEKIT_API_SECRET) < 32:
        weak.append("LIVEKIT_API_SECRET")
    return [
        Error(
            f"{name} is weak: it must be at least 32 characters, generated, and "
            "shared with nothing else.",
            id="core.E005",
        )
        for name in weak
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
