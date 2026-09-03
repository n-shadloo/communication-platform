import os

from core.env import env_list

from .base import *  # noqa

DEBUG = True
ALLOWED_HOSTS = ["127.0.0.1", "localhost", "testserver"]
ALLOWED_WS_ORIGINS = env_list("ALLOWED_WS_ORIGINS", default=["http://localhost"])
# Dev-only fallbacks so `manage.py`/tests run without a full secret set.
os.environ.setdefault("DJANGO_SECRET_KEY", "dev-insecure-secret-key")
os.environ.setdefault("JWT_SIGNING_KEY", "dev-insecure-jwt-key")
SECRET_KEY = os.environ["DJANGO_SECRET_KEY"]
SIMPLE_JWT["SIGNING_KEY"] = os.environ["JWT_SIGNING_KEY"]
