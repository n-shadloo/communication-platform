import os

from channels.routing import ProtocolTypeRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")

django_asgi_app = get_asgi_application()

# The realtime phase adds a "websocket" entry here (ARCHITECTURE §A6); nothing else
# about this file needs to change.
application = ProtocolTypeRouter({
    "http": django_asgi_app,
})
