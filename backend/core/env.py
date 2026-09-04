import os


class ImproperlyConfigured(Exception):
    pass


_UNSET = object()


def env(key, default=_UNSET):
    val = os.environ.get(key, default)
    if val is _UNSET:
        raise ImproperlyConfigured(f"Missing required env var: {key}")
    return val


def env_bool(key, default=False):
    v = os.environ.get(key)
    if v is None:
        return default
    return v.strip().lower() in {"1", "true", "yes", "on"}


def env_int(key, default=None):
    v = os.environ.get(key)
    return int(v) if v is not None and v != "" else default


def env_list(key, default=None):
    v = os.environ.get(key)
    if not v:
        return list(default) if default is not None else []
    return [item.strip() for item in v.split(",") if item.strip()]
