from django.urls import path

from . import views

urlpatterns = [
    path("me/identity", views.MyIdentityView.as_view(), name="my-identity"),
    path("me/devicelog", views.MyDeviceLogView.as_view(), name="my-devicelog"),
    # Register (POST) and the own-device list (GET) share one path; the view accepts
    # a register-scope token for POST only.
    path("me/devices", views.MyDevicesView.as_view(), name="my-devices"),
    path(
        "me/devices/<uuid:device_id>",
        views.MyDeviceDetailView.as_view(),
        name="my-device-detail",
    ),
    path(
        "me/devices/<uuid:device_id>/prekeys",
        views.MyPrekeysView.as_view(),
        name="my-prekeys",
    ),
    path(
        "me/devices/<uuid:device_id>/prekeys/count",
        views.MyPrekeysCountView.as_view(),
        name="my-prekeys-count",
    ),
    path(
        "users/<uuid:user_id>/identity",
        views.PeerIdentityView.as_view(),
        name="peer-identity",
    ),
    path(
        "users/<uuid:user_id>/devicelog",
        views.PeerDeviceLogView.as_view(),
        name="peer-devicelog",
    ),
    path(
        "users/<uuid:user_id>/devices",
        views.PeerDevicesView.as_view(),
        name="peer-devices",
    ),
    path(
        "users/<uuid:user_id>/keys/claim",
        views.ClaimKeysView.as_view(),
        name="claim-keys",
    ),
]
