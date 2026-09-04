from .base import *  # noqa

# All of these come from the environment; no insecure fallback exists in prod.
DEBUG = False
SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
# `__Host-`: a browser accepts the cookie only over HTTPS, with no `Domain` and
# with `Path=/`, so a sibling site on the same domain — the VPS serves two other
# projects — cannot set one for the panel, and no broader cookie of the same name
# can shadow it. Production only: the prefix is refused over plain HTTP.
SESSION_COOKIE_NAME = "__Host-sessionid"
CSRF_COOKIE_NAME = "__Host-csrftoken"
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
# TLS is terminated by nginx; Django trusts only the proxy's forwarded scheme.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
