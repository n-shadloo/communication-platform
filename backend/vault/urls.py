from django.urls import path
from . import views

urlpatterns = [
    path("me/keybackup", views.KeyBackupView.as_view()),
    path("me/history", views.HistoryView.as_view()),
    path("me/history/delete", views.HistoryDeleteView.as_view()),
    path("me/history/usage", views.HistoryUsageView.as_view()),
]
