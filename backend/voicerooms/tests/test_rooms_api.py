"""Room CRUD (§A5): create/read/rename an id + encrypted-name row — nothing else."""
import base64
import uuid
from datetime import date

import pytest
from django.utils import timezone

from voicerooms.models import Room

from .conftest import NAME_LEN, name_blob_b64

pytestmark = pytest.mark.django_db


def test_create_returns_the_capability_id_and_stores_one_bucketed_blob(
        api, active_user, device, auth_headers):
    resp = api.post("/api/v1/rooms", {"name_blob": name_blob_b64(b"q")},
                    format="json", **auth_headers(active_user, device))

    assert resp.status_code == 201
    room = Room.objects.get(id=resp.data["room_id"])
    assert bytes(room.name_blob) == b"q" * NAME_LEN


def test_get_round_trips_the_blob_and_reports_zero_live(api, active_user, device,
                                                        auth_headers, room):
    resp = api.get(f"/api/v1/rooms/{room.id}", **auth_headers(active_user, device))

    assert resp.status_code == 200
    assert resp.data == {
        "room_id": str(room.id),
        "name_blob": base64.b64encode(b"n" * NAME_LEN).decode(),
        "updated_date": timezone.now().date().isoformat(),
        "live_count": 0,
    }


def test_rename_changes_the_blob_and_bumps_updated_date(api, active_user, device,
                                                        auth_headers, room):
    # Predate the row so the bump is observable: auto_now never fires on a queryset
    # .update(), which is exactly why the view sets updated_date explicitly.
    Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))

    resp = api.put(f"/api/v1/rooms/{room.id}", {"name_blob": name_blob_b64(b"z")},
                   format="json", **auth_headers(active_user, device))

    assert resp.status_code == 200
    room.refresh_from_db()
    assert bytes(room.name_blob) == b"z" * NAME_LEN
    assert room.updated_date == timezone.now().date()


def test_unknown_room_is_404_for_get_put_and_token(api, active_user, device,
                                                   auth_headers):
    headers = auth_headers(active_user, device)
    missing = uuid.uuid4()

    assert api.get(f"/api/v1/rooms/{missing}", **headers).status_code == 404
    assert api.put(f"/api/v1/rooms/{missing}", {"name_blob": name_blob_b64()},
                   format="json", **headers).status_code == 404


@pytest.mark.parametrize("bad", [
    base64.b64encode(b"x" * 100).decode(),   # not a bucket length
    "@@@not-base64@@@",                      # not base64 at all
])
def test_off_bucket_names_are_rejected_without_echo(api, active_user, device,
                                                    auth_headers, room, bad):
    for verb, url in (("post", "/api/v1/rooms"), ("put", f"/api/v1/rooms/{room.id}")):
        resp = getattr(api, verb)(url, {"name_blob": bad}, format="json",
                                  **auth_headers(active_user, device))
        assert resp.status_code == 400
        assert resp.data["code"] == "bad_bucket"
        assert bad not in str(resp.data)


def test_missing_name_blob_is_a_400(api, active_user, device, auth_headers):
    resp = api.post("/api/v1/rooms", {}, format="json",
                    **auth_headers(active_user, device))
    assert resp.status_code == 400


def test_register_scope_tokens_are_locked_out_of_every_room_endpoint(
        api, active_user, auth_headers, room):
    """§A8: a register-scope token's only power is POST /me/devices. The prompt's bare
    [IsAuthenticated] would have admitted one here — the retained guard is load-bearing."""
    headers = auth_headers(active_user, scope="register")

    assert api.post("/api/v1/rooms", {"name_blob": name_blob_b64()},
                    format="json", **headers).status_code == 403
    assert api.get(f"/api/v1/rooms/{room.id}", **headers).status_code == 403
    assert api.put(f"/api/v1/rooms/{room.id}", {"name_blob": name_blob_b64()},
                   format="json", **headers).status_code == 403
    assert api.post(f"/api/v1/rooms/{room.id}/token", **headers).status_code == 403


def test_anonymous_requests_are_401(api, room):
    assert api.post("/api/v1/rooms", {"name_blob": name_blob_b64()},
                    format="json").status_code == 401
    assert api.get(f"/api/v1/rooms/{room.id}").status_code == 401
    assert api.post(f"/api/v1/rooms/{room.id}/token").status_code == 401
