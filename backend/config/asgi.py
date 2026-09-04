import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
# Populates the app registry. Every import below reads a Django model, directly
# or through a router, so none of them may move above this line.
django_asgi_app = get_asgi_application()

from channels.routing import URLRouter  # noqa: E402
from django.urls import path  # noqa: E402

from api.app import create_app, wrap  # noqa: E402
from realtime.consumers import GatewayConsumer  # noqa: E402

websocket_urlpatterns = [path("ws", GatewayConsumer.as_asgi())]
websocket_application = URLRouter(websocket_urlpatterns)

# Exported for the test client, which enters this application's lifespan.
api_application = create_app(django_asgi_app)
http_application = wrap(api_application)


async def application(scope, receive, send):
    """Route by scope type.

    The Channels router still serves every WebSocket; run 06 moves it. Lifespan
    goes to the FastAPI side, which is the only half of the process that answers
    it — Django implements no lifespan at all.
    """
    if scope["type"] == "websocket":
        await websocket_application(scope, receive, send)
        return
    await http_application(scope, receive, send)
