import os

# Dev-only fallbacks so `manage.py` and the suite run without a full secret set.
# They are set before the star import, because `base` reads both at import time.
os.environ.setdefault("DJANGO_SECRET_KEY", "dev-insecure-secret-key")
os.environ.setdefault("JWT_SIGNING_KEY", "dev-insecure-jwt-key")

from core.env import env_list  # noqa: E402

from .base import *  # noqa: E402, F403

DEBUG = True
ALLOWED_HOSTS = ["127.0.0.1", "localhost", "testserver"]
ALLOWED_WS_ORIGINS = env_list("ALLOWED_WS_ORIGINS", default=["http://localhost"])
