from django.urls import path

from . import views

urlpatterns = [
    path("rooms", views.RoomListCreateView.as_view()),
    path("rooms/<uuid:room_id>", views.RoomDetailView.as_view()),
    path("rooms/<uuid:room_id>/token", views.RoomTokenView.as_view()),
]
