from django.contrib import admin
from django.urls import include, path

from core.env import env

# Operator-chosen: the stock admin behind a non-obvious path is one less thing to
# scan for.
ADMIN_PATH = env("ADMIN_PATH", default="admin/")

# The routes of core, accounts and vault are served by FastAPI and are absent
# here. What remains is the admin plus the apps that have not moved; run 05
# empties the rest of this list.
urlpatterns = [
    path(ADMIN_PATH, admin.site.urls),
    path("api/v1/", include("devices.urls")),
    path("api/v1/", include("messaging.urls")),
    path("api/v1/", include("attachments.urls")),
    path("api/v1/", include("voicerooms.urls")),
]
