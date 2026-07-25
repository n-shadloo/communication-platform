from django.urls import path

from . import views

urlpatterns = [
    path("me/keybackup", views.KeyBackupView.as_view()),
]
