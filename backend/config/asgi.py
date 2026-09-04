import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
# Populates the app registry. Every import below reads a Django model, directly
# or through a router, so none of them may move above this line.
django_asgi_app = get_asgi_application()

from api.app import create_app, wrap  # noqa: E402

# The FastAPI application answers every scope: HTTP through its routers, with the
# Django application behind them for the admin, and the WebSocket scope through
# the `/ws` route of `realtime/gateway.py`. There is no dispatcher above it.
api_application = create_app(django_asgi_app)

# Exported under both names: `application` is what the server runs and what the
# tests drive, and `api_application` is the FastAPI object itself, which the
# route-table and lifespan helpers need unwrapped.
application = wrap(api_application)
