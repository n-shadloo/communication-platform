from django.contrib import admin
from django.urls import include, path

from core.env import env

# Operator-chosen: the stock admin behind a non-obvious path is one less thing to scan
# for (ARCHITECTURE §A3).
ADMIN_PATH = env("ADMIN_PATH", default="admin/")

urlpatterns = [
    path(ADMIN_PATH, admin.site.urls),
    path("api/v1/", include("core.urls")),
    path("api/v1/", include("accounts.urls")),
    path("api/v1/", include("messaging.urls")),
    path("api/v1/", include("attachments.urls")),
]
