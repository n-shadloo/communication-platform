"""No server-side history, provably.

The design decision is that history sync is client-to-client on new-device
enrollment: the server stores no long-term message history anywhere. These tests
pin the removal — no model, no table, no route, no prune path — so history cannot
quietly grow back, and prove the key backup survived the removal intact.
"""

import base64

import pytest
from django.apps import apps
from django.db import connection

from vault.models import KeyBackup

from .conftest import KEYBACKUP_URL, backup_blob

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)

REMOVED_ROUTES = (
    ("GET", "/api/v1/me/history"),
    ("POST", "/api/v1/me/history"),
    ("POST", "/api/v1/me/history/delete"),
    ("GET", "/api/v1/me/history/usage"),
)


@pytest.mark.parametrize("method, url", REMOVED_ROUTES)
def test_every_history_route_is_gone(http, active_user, device, bearer, method, url):
    response = http.request(method, url, headers=bearer(active_user, device))

    assert response.status_code == 404


def test_no_history_model_or_table_exists():
    assert not any(model.__name__ == "HistoryRecord" for model in apps.get_models())
    assert "vault_historyrecord" not in connection.introspection.table_names()


def test_no_registered_model_stores_message_content_past_the_queue():
    """The queue (delete-on-ack, TTL-capped) is the only place envelope-shaped
    ciphertext may rest. Every other blob column holds non-message state: profile,
    label, key backup, device-log records, room names."""
    from core.fields import OpaqueBlobField
    from messaging.models import QueuedEnvelope

    allowed = {
        "accounts.ProfileBlob.blob",
        "devices.Device.label_blob",
        "devices.DeviceLogRecord.blob",
        "vault.KeyBackup.blob",
        "messaging.QueuedEnvelope.blob",
        "voicerooms.Room.name_blob",
    }
    found = {
        f"{model._meta.app_label}.{model.__name__}.{field.name}"
        for model in apps.get_models()
        for field in model._meta.get_fields()
        if isinstance(field, OpaqueBlobField)
    }
    assert found == allowed, (
        "an unreviewed blob store appeared — if it can hold message content past "
        f"delivery, it re-creates server-side history: {found - allowed}"
    )
    assert QueuedEnvelope._meta.get_field("blob").bucket_set  # the queue stays bucketed


def test_the_key_backup_still_works_end_to_end(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    payload = backup_blob(b"Z")

    assert (
        http.put(
            KEYBACKUP_URL, json={"blob": payload, "version": 3}, headers=headers
        ).status_code
        == 200
    )

    assert http.get(KEYBACKUP_URL, headers=headers).json() == {
        "blob": payload,
        "version": 3,
    }


def test_an_overwritten_backup_leaves_no_earlier_copy_anywhere_in_the_table(
    http, active_user, device, bearer
):
    """Replacing the backup is a replacement, not an append. The bytes of the
    superseded blob must not survive in any row — a kept previous version is a
    two-entry history, and the argument that stops it at two stops it nowhere."""
    headers = bearer(active_user, device)
    superseded = backup_blob(b"1")
    current = backup_blob(b"2")

    http.put(KEYBACKUP_URL, json={"blob": superseded, "version": 1}, headers=headers)
    http.put(KEYBACKUP_URL, json={"blob": current, "version": 2}, headers=headers)

    stored = [bytes(row.blob) for row in KeyBackup.objects.all()]
    assert stored == [base64.b64decode(current)]
    assert base64.b64decode(superseded) not in stored


def test_the_route_hands_back_only_the_current_version(http, active_user, device, bearer):
    """Three writes, one readable answer. There is no parameter, header or body
    that reaches an older one, because no older one is kept."""
    headers = bearer(active_user, device)
    earlier = [backup_blob(b"1"), backup_blob(b"2")]
    for version, blob in enumerate(earlier, start=1):
        http.put(KEYBACKUP_URL, json={"blob": blob, "version": version}, headers=headers)
    newest = backup_blob(b"3")
    http.put(KEYBACKUP_URL, json={"blob": newest, "version": 3}, headers=headers)

    body = http.get(KEYBACKUP_URL, headers=headers)

    assert body.json() == {"blob": newest, "version": 3}
    assert all(blob not in body.text for blob in earlier)


def test_the_vault_router_carries_no_parameter_and_no_extra_verb():
    """A history API needs a way to name one of many: a path parameter, a range
    query or a verb that appends. The router has one fixed path and the two verbs
    that replace and read a single value."""
    from vault.routes import router

    assert {(route.path, tuple(sorted(route.methods))) for route in router.routes} == {
        ("/me/keybackup", ("GET",)),
        ("/me/keybackup", ("PUT",)),
    }
    assert all("{" not in route.path for route in router.routes)


@pytest.mark.parametrize(
    "url",
    [
        "/api/v1/me/keybackup/versions",
        "/api/v1/me/keybackup/history",
        "/api/v1/me/history/export",
    ],
)
def test_no_backup_history_path_answers_anything(http, active_user, device, bearer, url):
    response = http.get(url, headers=bearer(active_user, device))

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"
