from django.conf import settings
from django.contrib import admin
from django.contrib.staticfiles.urls import staticfiles_urlpatterns
from django.urls import path

from core.env import env

# Operator-chosen: the stock admin behind a non-obvious path is one less thing to
# scan for.
ADMIN_PATH = env("ADMIN_PATH", default="admin/")

# Every route of this API is served by FastAPI. What Django answers is the admin,
# and nothing else; `api.app.django_paths` is what refuses it any other path.
urlpatterns = [path(ADMIN_PATH, admin.site.urls)]

if settings.DEBUG:
    # The admin's own CSS and JS. daphne serves this process rather than
    # `runserver`, so nothing else would serve them in development; in production
    # nginx serves STATIC_ROOT and this list is empty.
    urlpatterns += staticfiles_urlpatterns()
