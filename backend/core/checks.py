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
    # flush the rate counters and the lockout and publish frames on the fan-out
    # bus. ADR-0018. A development machine runs Redis
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

    # Django checks the strength of SECRET_KEY itself (security.W009). These are
    # the two secrets this process signs with, and each is weighed against what a
    # holder of it could do.
    errors = []
    # The signing key mints a token for any account. HS256 wants a key of at least
    # 256 bits, and nothing else refused a short value, the development fallback,
    # or a key shared with SECRET_KEY.
    key = settings.JWT_SIGNING_KEY
    if len(key) < 32 or key in ("dev-insecure-jwt-key", settings.SECRET_KEY):
        errors.append(
            Error(
                "JWT_SIGNING_KEY is weak: it must be at least 32 characters, "
                "generated, and shared with nothing else.",
                id="core.E005",
            )
        )
    # The relay secret mints a credential for coturn, and it is weighed only when
    # `TURN_URLS` names a relay to mint one for: a deployment that serves no voice
    # reads the secret nowhere, and refusing it a value would refuse a deployment
    # that is correct.
    if settings.TURN_URLS and len(settings.TURN_STATIC_AUTH_SECRET) < 32:
        errors.append(
            Error(
                "TURN_STATIC_AUTH_SECRET is weak: TURN_URLS names a relay, so the "
                "secret must be at least 32 characters and generated. It is one "
                "value in two places — this variable and `static-auth-secret` in "
                "the coturn configuration.",
                id="core.E005",
            )
        )
    return errors
