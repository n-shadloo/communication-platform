"""Room CRUD: create/read/rename an id plus encrypted-name row, nothing else."""

import base64
import uuid
from datetime import date

import pytest
from django.utils import timezone

from voicerooms.models import Room

from .conftest import NAME_LEN, name_blob_b64

# transaction=True because every route runs its unit of work through the ORM
# bracket of `api.orm.run_unit`, which closes the connection a wrapping test
# transaction would need.
pytestmark = pytest.mark.django_db(transaction=True)

ROOMS_URL = "/api/v1/rooms"


def test_create_returns_the_capability_id_and_stores_one_bucketed_blob(
    http, active_user, device, bearer
):
    resp = http.post(
        ROOMS_URL,
        json={"name_blob": name_blob_b64(b"q")},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 201
    room = Room.objects.get(id=resp.json()["room_id"])
    assert bytes(room.name_blob) == b"q" * NAME_LEN


def test_an_unknown_field_is_rejected(http, active_user, device, bearer):
    resp = http.post(
        ROOMS_URL,
        json={"name_blob": name_blob_b64(b"q"), "junk": 1},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "junk" in resp.json()["detail"]


def test_get_round_trips_the_blob_and_reports_zero_live(
    http, active_user, device, bearer, room
):
    resp = http.get(f"{ROOMS_URL}/{room.id}", headers=bearer(active_user, device))

    assert resp.status_code == 200
    assert resp.json() == {
        "room_id": str(room.id),
        "name_blob": base64.b64encode(b"n" * NAME_LEN).decode(),
        "updated_date": timezone.now().date().isoformat(),
        "live_count": 0,
    }


def test_rename_changes_the_blob_and_bumps_updated_date(
    http, active_user, device, bearer, room
):
    # Predate the row so the bump is observable: auto_now never fires on a queryset
    # .update(), which is exactly why the service sets updated_date explicitly.
    Room.objects.filter(id=room.id).update(updated_date=date(2020, 1, 1))

    resp = http.put(
        f"{ROOMS_URL}/{room.id}",
        json={"name_blob": name_blob_b64(b"z")},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 200
    assert resp.content == b""
    room.refresh_from_db()
    assert bytes(room.name_blob) == b"z" * NAME_LEN
    assert room.updated_date == timezone.now().date()


def test_unknown_room_is_404_for_get_and_put(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    missing = uuid.uuid4()

    read = http.get(f"{ROOMS_URL}/{missing}", headers=headers)
    renamed = http.put(
        f"{ROOMS_URL}/{missing}", json={"name_blob": name_blob_b64()}, headers=headers
    )

    for resp in (read, renamed):
        assert resp.status_code == 404
        assert resp.json() == {"code": "not_found", "detail": "No such room."}


def test_a_malformed_room_id_is_an_invalid_request(http, active_user, device, bearer):
    """A path segment that is not a UUID is a client defect, not a missing room."""
    resp = http.get(f"{ROOMS_URL}/not-a-uuid", headers=bearer(active_user, device))

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "room_id" in resp.json()["detail"]


@pytest.mark.parametrize(
    "bad",
    [
        base64.b64encode(b"x" * 100).decode(),  # not a bucket length
        "@@@not-base64@@@",  # not base64 at all
    ],
)
def test_off_bucket_names_are_rejected_without_echo(
    http, active_user, device, bearer, room, bad
):
    headers = bearer(active_user, device)
    for verb, url in (("PUT", f"{ROOMS_URL}/{room.id}"), ("POST", ROOMS_URL)):
        resp = http.request(verb, url, json={"name_blob": bad}, headers=headers)

        assert resp.status_code == 400
        assert resp.json() == {"code": "bad_bucket", "detail": "Invalid payload."}
        assert bad not in resp.text


def test_missing_name_blob_is_an_invalid_request(http, active_user, device, bearer):
    resp = http.post(ROOMS_URL, json={}, headers=bearer(active_user, device))

    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"
    assert "name_blob" in resp.json()["detail"]


def test_register_scope_tokens_are_locked_out_of_every_room_endpoint(
    http, active_user, register_bearer, room
):
    """A register-scope token's only power is POST /me/devices; a requirement that
    only checked identity would have admitted one here."""
    headers = register_bearer(active_user)
    name = {"name_blob": name_blob_b64()}

    assert http.post(ROOMS_URL, json=name, headers=headers).status_code == 403
    assert http.get(f"{ROOMS_URL}/{room.id}", headers=headers).status_code == 403
    assert (
        http.put(f"{ROOMS_URL}/{room.id}", json=name, headers=headers).status_code == 403
    )
    assert http.post(f"{ROOMS_URL}/{room.id}/token", headers=headers).status_code == 403


def test_anonymous_requests_are_401(http, room):
    assert http.post(ROOMS_URL, json={"name_blob": name_blob_b64()}).status_code == 401
    assert http.get(f"{ROOMS_URL}/{room.id}").status_code == 401
    assert http.post(f"{ROOMS_URL}/{room.id}/token").status_code == 401
