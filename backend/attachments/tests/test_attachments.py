"""The attachment store: the capability id is the only gate."""

import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS

UPLOAD_URL = "/api/v1/attachments"
SMALLEST = min(ATTACHMENT_BUCKETS)


def upload(api, headers, payload=None, size=SMALLEST):
    body = payload if payload is not None else b"\x01" * size
    return api.post(
        UPLOAD_URL,
        {"blob": SimpleUploadedFile("blob", body)},
        format="multipart",
        **headers,
    )


@pytest.mark.django_db
def test_an_upload_returns_a_43_char_capability_id(
    api, active_user, device, auth_headers, attachments_root
):
    resp = upload(api, auth_headers(active_user, device))

    assert resp.status_code == 201
    body = resp.json()
    assert len(body["attachment_id"]) == 43
    assert body["size"] == SMALLEST
    attachment = Attachment.objects.get(id=body["attachment_id"])
    # Bytes land under a two-char shard of the id, never under a client-chosen name.
    stored = attachments_root / body["attachment_id"][:2] / body["attachment_id"]
    assert stored.read_bytes() == b"\x01" * SMALLEST
    assert attachment.disk_path() == str(stored)


@pytest.mark.django_db
def test_capability_ids_are_unguessable_and_distinct(
    api, active_user, device, auth_headers
):
    first = upload(api, auth_headers(active_user, device)).json()["attachment_id"]
    second = upload(api, auth_headers(active_user, device)).json()["attachment_id"]

    assert first != second
    # base64url of 32 random bytes: no padding, no path separators.
    for cap in (first, second):
        assert "/" not in cap and "+" not in cap and "=" not in cap


@pytest.mark.django_db
def test_an_off_bucket_upload_is_rejected(api, active_user, device, auth_headers):
    resp = upload(
        api, auth_headers(active_user, device), payload=b"\x01" * (SMALLEST - 1)
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_bucket"
    assert Attachment.objects.count() == 0


@pytest.mark.django_db
def test_a_missing_file_is_a_400(api, active_user, device, auth_headers):
    resp = api.post(
        UPLOAD_URL, {}, format="multipart", **auth_headers(active_user, device)
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "bad_request"


@pytest.mark.django_db
def test_the_quota_is_enforced_per_user(
    api, active_user, device, auth_headers, settings, bob, bob_device
):
    settings.ATTACH_USER_QUOTA_BYTES = SMALLEST

    first = upload(api, auth_headers(active_user, device))
    second = upload(api, auth_headers(active_user, device))
    # The quota is per uploader, so another account is unaffected.
    other = upload(api, auth_headers(bob, bob_device))

    assert first.status_code == 201
    assert second.status_code == 413
    assert second.json()["code"] == "quota_exceeded"
    assert other.status_code == 201
    assert Attachment.objects.filter(uploader_id=active_user.id).count() == 1


@pytest.mark.django_db
def test_a_download_hands_the_bytes_to_nginx(api, active_user, device, auth_headers):
    cap = upload(api, auth_headers(active_user, device)).json()["attachment_id"]

    resp = api.get(f"{UPLOAD_URL}/{cap}", **auth_headers(active_user, device))

    assert resp.status_code == 200
    assert resp["X-Accel-Redirect"] == f"/_protected_attachments/{cap[:2]}/{cap}"
    # Opaque bytes: fixed type, never sniffed, never rendered, never cached.
    assert resp["Content-Type"] == "application/octet-stream"
    assert resp["X-Content-Type-Options"] == "nosniff"
    assert resp["Content-Disposition"] == "attachment"
    assert resp["Cache-Control"] == "private, no-store"
    # Django hands off the path; it never streams the bytes itself.
    assert resp.content == b""


@pytest.mark.django_db
def test_any_authenticated_user_may_fetch_by_capability(
    api, active_user, device, auth_headers, bob, bob_device
):
    """The unguessable id is the access control; a per-recipient ACL would rebuild
    the conversation graph."""
    cap = upload(api, auth_headers(active_user, device)).json()["attachment_id"]

    resp = api.get(f"{UPLOAD_URL}/{cap}", **auth_headers(bob, bob_device))

    assert resp.status_code == 200


@pytest.mark.django_db
@pytest.mark.parametrize("missing", ["a" * 43, "nope", "..", "%2e%2e%2fetc%2fpasswd"])
def test_an_unknown_capability_is_a_404(api, active_user, device, auth_headers, missing):
    resp = api.get(f"{UPLOAD_URL}/{missing}", **auth_headers(active_user, device))

    assert resp.status_code == 404
    assert "X-Accel-Redirect" not in resp


@pytest.mark.django_db
def test_anonymous_access_is_rejected(api, active_user, device, auth_headers):
    cap = upload(api, auth_headers(active_user, device)).json()["attachment_id"]

    assert api.post(UPLOAD_URL, {}, format="multipart").status_code == 401
    assert api.get(f"{UPLOAD_URL}/{cap}").status_code == 401


@pytest.mark.django_db
def test_a_register_scope_token_cannot_upload_or_download(
    api, active_user, device, auth_headers
):
    cap = upload(api, auth_headers(active_user, device)).json()["attachment_id"]
    register = auth_headers(active_user, scope="register")

    assert upload(api, register).status_code == 403
    assert api.get(f"{UPLOAD_URL}/{cap}", **register).status_code == 403


@pytest.mark.django_db
def test_the_model_stores_no_recipient_or_acl_data():
    names = {f.name for f in Attachment._meta.get_fields()}

    assert names == {"id", "uploader", "size", "created_date"}
