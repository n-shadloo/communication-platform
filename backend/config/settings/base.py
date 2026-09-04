from pathlib import Path

from core.env import env, env_int, env_list

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

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ]
        },
    }
]

AUTH_USER_MODEL = "accounts.User"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": env("POSTGRES_DB"),
        "USER": env("POSTGRES_USER"),
        "PASSWORD": env("POSTGRES_PASSWORD"),
        "HOST": env("POSTGRES_HOST", default="127.0.0.1"),
        "PORT": env("POSTGRES_PORT", default="5432"),
        "CONN_MAX_AGE": env_int("DB_CONN_MAX_AGE", default=0),
        "OPTIONS": {
            "pool": {
                "min_size": env_int("DB_POOL_MIN_SIZE", default=1),
                "max_size": env_int("DB_POOL_MAX_SIZE", default=16),
                "timeout": env_int("DB_POOL_TIMEOUT", default=10),
            }
        },
    }
}

REDIS_URL = env("REDIS_URL", default="redis://127.0.0.1:6379/0")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
    }
}
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [REDIS_URL]},
    }
}

# Argon2id first. Password hashing protects auth only, never content.
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.Argon2PasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
]
AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 10},
    },
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

# --- Authentication (ADR-0006): PyJWT, and no token table -----------------------
# A token table would be a per-device login record at rest, which the threat model
# refuses to keep. Revocation is two counters on the device row instead.
JWT_SIGNING_KEY = env("JWT_SIGNING_KEY")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = env_int("ACCESS_MIN", default=15)
REFRESH_TOKEN_DAYS = env_int("REFRESH_DAYS", default=14)
REGISTER_SCOPE_ACCESS_MIN = env_int("REGISTER_SCOPE_ACCESS_MIN", default=10)

# --- Rate limits (ADR-0010) -----------------------------------------------------
# One table, read by the FastAPI limiter and by the REST Framework throttle of the
# apps that have not moved. A scope both stacks serve counts once on each during
# the transition; run 05 leaves one counter.
THROTTLE_RATES = {
    "register": env("THROTTLE_REGISTER", default="10/hour"),
    "login": env("THROTTLE_LOGIN", default="20/hour"),
    "refresh": env("THROTTLE_REFRESH", default="120/hour"),
    "accounts": env("THROTTLE_ACCOUNTS", default="120/min"),
    "claim": env("THROTTLE_CLAIM", default="120/min"),
    "envelopes": env("THROTTLE_ENVELOPES", default="600/min"),
    "attachments": env("THROTTLE_ATTACHMENTS", default="60/min"),
    "roomtoken": env("THROTTLE_ROOMTOKEN", default="60/min"),
}

# --- Request limits (ADR-0014) --------------------------------------------------
# One process on 1 GB of RAM has no headroom for an unbounded body or a request
# that never ends, and no second host to fail over to. The upload class covers the
# routes the Django catch-all still serves, whose largest body is a 64 MiB
# attachment; nginx caps the same value at 70m.
REQUEST_DEADLINE_SECONDS = env_int("REQUEST_DEADLINE_SECONDS", default=15)
UPLOAD_DEADLINE_SECONDS = env_int("UPLOAD_DEADLINE_SECONDS", default=120)
BODY_CAP_JSON_BYTES = env_int("BODY_CAP_JSON_BYTES", default=16 * 1024)
BODY_CAP_BACKUP_BYTES = env_int("BODY_CAP_BACKUP_BYTES", default=2 * 1024 * 1024)
BODY_CAP_UPLOAD_BYTES = env_int("BODY_CAP_UPLOAD_BYTES", default=70 * 1024 * 1024)

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
    "DEFAULT_THROTTLE_RATES": THROTTLE_RATES,
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    "EXCEPTION_HANDLER": "core.exceptions.api_exception_handler",
}

# Storage limits and retention.
ATTACHMENTS_ROOT = Path(env("ATTACHMENTS_ROOT", default=str(BASE_DIR / "media_root")))
ATTACH_USER_QUOTA_BYTES = env_int("ATTACH_USER_QUOTA_BYTES", default=2 * 1024**3)
ATTACH_TTL_DAYS = env_int("ATTACH_TTL_DAYS", default=30)
# 7 days bounds what a live seizure captures to at most a week of *undelivered*
# ciphertext (delivery deletes on ack). It is also the window an offline device
# has to collect its mail: an envelope pruned first may have carried a ratchet
# message or a group control event, and the device must then repair the affected
# pairwise sessions — see queue_pruned_through.
ENVELOPE_TTL_DAYS = env_int("ENVELOPE_TTL_DAYS", default=7)
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
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "plain",
            "filters": ["scrub"],
        }
    },
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        # No request/access logging: never record method, path, or bodies.
        "django.request": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "django.server": {"handlers": ["console"], "level": "ERROR", "propagate": False},
        "daphne": {"handlers": ["console"], "level": "WARNING", "propagate": False},
    },
}
