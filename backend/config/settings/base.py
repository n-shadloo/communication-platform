from datetime import timedelta
from pathlib import Path

from core.env import env, env_bool, env_int, env_list

BASE_DIR = Path(__file__).resolve().parent.parent.parent

SECRET_KEY = env("DJANGO_SECRET_KEY")
DEBUG = False
ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS", default=[])

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "core",
    "accounts",
    "devices",
    "vault",
    "messaging",
    "attachments",
    "voicerooms",
    "realtime",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",  # admin only; API is token-auth
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
ASGI_APPLICATION = "config.asgi.application"
WSGI_APPLICATION = None  # ASGI-only

TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [],
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
        "django.contrib.messages.context_processors.messages",
    ]},
}]

AUTH_USER_MODEL = "accounts.User"

DATABASES = {"default": {
    "ENGINE": "django.db.backends.postgresql",
    "NAME": env("POSTGRES_DB"),
    "USER": env("POSTGRES_USER"),
    "PASSWORD": env("POSTGRES_PASSWORD"),
    "HOST": env("POSTGRES_HOST", default="127.0.0.1"),
    "PORT": env("POSTGRES_PORT", default="5432"),
    "CONN_MAX_AGE": env_int("DB_CONN_MAX_AGE", default=60),
}}

REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379/0")
CACHES = {"default": {
    "BACKEND": "django.core.cache.backends.redis.RedisCache",
    "LOCATION": REDIS_URL,
}}
CHANNEL_LAYERS = {"default": {
    "BACKEND": "channels_redis.core.RedisChannelLayer",
    "CONFIG": {"hosts": [REDIS_URL]},
}}

# Argon2id first. Password hashing protects auth only, never content.
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
]
AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
     "OPTIONS": {"min_length": 10}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "static_root"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# No email is ever sent by this system.
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": ["accounts.auth.DeviceJWTAuthentication"],
    # Fail closed on scope as well as identity: DeviceJWTAuthentication authenticates
    # register-scope tokens, so IsAuthenticated alone would admit them to any view
    # that forgets the check. POST /me/devices is the one endpoint expected to opt
    # down.
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
        "accounts.permissions.IsFullScope",
    ],
    "DEFAULT_THROTTLE_CLASSES": ["rest_framework.throttling.ScopedRateThrottle"],
    "DEFAULT_THROTTLE_RATES": {
        "register": env("THROTTLE_REGISTER", default="10/hour"),
        "login": env("THROTTLE_LOGIN", default="20/hour"),
        "refresh": env("THROTTLE_REFRESH", default="120/hour"),
        "accounts": env("THROTTLE_ACCOUNTS", default="120/min"),
        "claim": env("THROTTLE_CLAIM", default="120/min"),
        "envelopes": env("THROTTLE_ENVELOPES", default="600/min"),
        "attachments": env("THROTTLE_ATTACHMENTS", default="60/min"),
        "roomtoken": env("THROTTLE_ROOMTOKEN", default="60/min"),
    },
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    "EXCEPTION_HANDLER": "core.exceptions.api_exception_handler",
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env_int("ACCESS_MIN", default=15)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env_int("REFRESH_DAYS", default=14)),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "ALGORITHM": "HS256",
    "SIGNING_KEY": env("JWT_SIGNING_KEY"),
    "AUTH_HEADER_TYPES": ("Bearer",),
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "user_id",
}

REGISTER_SCOPE_ACCESS_MIN = env_int("REGISTER_SCOPE_ACCESS_MIN", default=10)

# Storage limits and retention.
ATTACHMENTS_ROOT = Path(env("ATTACHMENTS_ROOT", default=str(BASE_DIR / "media_root")))
ATTACH_USER_QUOTA_BYTES = env_int("ATTACH_USER_QUOTA_BYTES", default=2 * 1024**3)
ATTACH_TTL_DAYS = env_int("ATTACH_TTL_DAYS", default=30)
# 7 days bounds what a live seizure captures to at most a week of *undelivered*
# ciphertext (delivery deletes on ack). It is also a group-membership parameter:
# an envelope pruned before an offline device collects it may have been an MLS
# commit, leaving that device permanently desynced until peers re-add it — see
# queue_pruned_through.
ENVELOPE_TTL_DAYS = env_int("ENVELOPE_TTL_DAYS", default=7)
# Stale MLS KeyPackages are rotated out so a claimed package is never too old for
# the joiner's ciphersuite/credential expectations; the last-resort package is
# exempt (it is the exhausted-pool fallback and replaced only by upload).
KEYPACKAGE_TTL_DAYS = env_int("KEYPACKAGE_TTL_DAYS", default=30)
MAX_DEVICES_PER_USER = env_int("MAX_DEVICES_PER_USER", default=10)

# Realtime gateway bounds.
ALLOWED_WS_ORIGINS = env_list("ALLOWED_WS_ORIGINS", default=[])
WS_MAX_FRAME = env_int("WS_MAX_FRAME", default=512 * 1024)
SIGNAL_MAX = env_int("SIGNAL_MAX", default=16 * 1024)

# Voice. The API secret is infrastructure, never a media key.
LIVEKIT_URL = env("LIVEKIT_URL", default="")
LIVEKIT_API_KEY = env("LIVEKIT_API_KEY", default="")
LIVEKIT_API_SECRET = env("LIVEKIT_API_SECRET", default="")
LIVEKIT_TOKEN_TTL_SECONDS = env_int("LIVEKIT_TOKEN_TTL_SECONDS", default=300)

# Security headers (prod tightens further).
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Strict"
CSRF_COOKIE_SAMESITE = "Strict"

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {"scrub": {"()": "core.logging_filters.ScrubFilter"}},
    "formatters": {"plain": {"format": "%(levelname)s %(name)s %(message)s"}},
    "handlers": {"console": {
        "class": "logging.StreamHandler", "formatter": "plain", "filters": ["scrub"],
    }},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        # No request/access logging: never record method, path, or bodies.
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "django.server": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "daphne": {"handlers": ["console"], "level": "WARNING", "propagate": False},
    },
}
