from django.urls import path

from . import views

urlpatterns = [
    path("auth/register", views.RegisterView.as_view(), name="register"),
    path("auth/login", views.LoginView.as_view(), name="login"),
    path("auth/refresh", views.RefreshView.as_view(), name="refresh"),
    path("auth/logout", views.LogoutView.as_view(), name="logout"),
    path("users", views.UserDirectoryView.as_view(), name="user-directory"),
    path(
        "users/<uuid:user_id>/profile",
        views.ProfileDetailView.as_view(),
        name="user-profile",
    ),
    path("me/profile", views.MyProfileView.as_view(), name="my-profile"),
]
