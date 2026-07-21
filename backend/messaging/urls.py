from django.urls import path

from . import views

urlpatterns = [
    path("envelopes", views.SendEnvelopesView.as_view(), name="send-envelopes"),
    path("me/envelopes", views.MyEnvelopesView.as_view(), name="my-envelopes"),
    path("me/envelopes/ack", views.AckEnvelopesView.as_view(), name="ack-envelopes"),
]
