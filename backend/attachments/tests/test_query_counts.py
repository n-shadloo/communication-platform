"""Query-shape guard for the upload path (§A5).

Counts include the two per-request auth queries `DeviceJWTAuthentication` makes.
"""
import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS

AUTH_QUERIES = 2
UPLOAD_URL = "/api/v1/attachments"
SMALLEST = min(ATTACHMENT_BUCKETS)


@pytest.mark.django_db
@pytest.mark.parametrize("existing", [0, 25])
def test_the_quota_check_is_one_aggregate_however_many_files_exist(
        api, active_user, device, auth_headers, django_assert_num_queries, existing):
    """The quota must stay a single SUM pushed to the database, never a fetch-and-add
    over the user's rows."""
    Attachment.objects.bulk_create([
        Attachment(uploader=active_user, size=SMALLEST) for _ in range(existing)
    ])
    headers = auth_headers(active_user, device)

    # 2 auth + 1 SUM aggregate + 1 insert.
    with django_assert_num_queries(AUTH_QUERIES + 2):
        resp = api.post(UPLOAD_URL, {"blob": SimpleUploadedFile("blob", b"\x01" * SMALLEST)},
                        format="multipart", **headers)

    assert resp.status_code == 201


@pytest.mark.django_db
def test_the_download_is_a_single_lookup(api, active_user, device, auth_headers,
                                         django_assert_num_queries):
    cap = api.post(UPLOAD_URL, {"blob": SimpleUploadedFile("blob", b"\x01" * SMALLEST)},
                   format="multipart",
                   **auth_headers(active_user, device)).json()["attachment_id"]
    headers = auth_headers(active_user, device)

    with django_assert_num_queries(AUTH_QUERIES + 1):
        resp = api.get(f"{UPLOAD_URL}/{cap}", **headers)

    assert resp.status_code == 200
