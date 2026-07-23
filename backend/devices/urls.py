from django.urls import path

from . import views

urlpatterns = [
    # Register (POST) and the own-device list (GET) share one path; the view accepts
    # a register-scope token for POST only.
    path("me/devices", views.MyDevicesView.as_view(), name="my-devices"),
    path("me/devices/<uuid:device_id>", views.MyDeviceDetailView.as_view(),
         name="my-device-detail"),
    path("me/devices/<uuid:device_id>/prekeys", views.MyPrekeysView.as_view(),
         name="my-prekeys"),
    path("me/devices/<uuid:device_id>/prekeys/count", views.MyPrekeysCountView.as_view(),
         name="my-prekeys-count"),
    path("me/devices/<uuid:device_id>/keypackages", views.MyKeyPackagesView.as_view(),
         name="my-keypackages"),
    path("me/devices/<uuid:device_id>/keypackages/count",
         views.MyKeyPackagesCountView.as_view(), name="my-keypackages-count"),
    path("users/<uuid:user_id>/devices", views.PeerDevicesView.as_view(),
         name="peer-devices"),
    path("users/<uuid:user_id>/keys/claim", views.ClaimKeysView.as_view(),
         name="claim-keys"),
    path("users/<uuid:user_id>/keypackages/claim", views.ClaimKeyPackagesView.as_view(),
         name="claim-keypackages"),
]
