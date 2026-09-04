from django.urls import path

from . import views

urlpatterns = [
    path("attachments", views.UploadAttachmentView.as_view(), name="upload-attachment"),
    path(
        "attachments/<str:attachment_id>",
        views.DownloadAttachmentView.as_view(),
        name="download-attachment",
    ),
]
