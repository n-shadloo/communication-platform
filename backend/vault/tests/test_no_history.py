"""No server-side history, provably.

The design decision is that history sync is client-to-client on new-device
enrollment: the server stores no long-term message history anywhere. These tests
pin the removal — no model, no table, no route, no prune path — so history cannot
quietly grow back, and prove the key backup survived the removal intact.
"""

import pytest
from django.apps import apps
from django.db import connection

from .conftest import KEYBACKUP_URL, backup_blob

pytestmark = pytest.mark.django_db

REMOVED_ROUTES = (
    ("get", "/api/v1/me/history"),
    ("post", "/api/v1/me/history"),
    ("post", "/api/v1/me/history/delete"),
    ("get", "/api/v1/me/history/usage"),
)


@pytest.mark.parametrize("method, url", REMOVED_ROUTES)
def test_every_history_route_is_gone(api, active_user, device, auth_headers, method, url):
    response = getattr(api, method)(url, **auth_headers(active_user, device))

    assert response.status_code == 404


def test_no_history_model_or_table_exists():
    assert not any(model.__name__ == "HistoryRecord" for model in apps.get_models())
    assert "vault_historyrecord" not in connection.introspection.table_names()


def test_no_registered_model_stores_message_content_past_the_queue():
    """The queue (delete-on-ack, TTL-capped) is the only place envelope-shaped
    ciphertext may rest. Every other blob column holds non-message state: profile,
    label, key backup, MLS KeyPackages, device-log records, room names."""
    from core.fields import OpaqueBlobField
    from messaging.models import QueuedEnvelope

    allowed = {
        "accounts.ProfileBlob.blob",
        "devices.Device.label_blob",
        "devices.KeyPackage.blob",
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


def test_the_key_backup_still_works_end_to_end(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    payload = backup_blob(b"Z")

    assert (
        api.put(
            KEYBACKUP_URL, {"blob": payload, "version": 3}, format="json", **headers
        ).status_code
        == 200
    )

    assert api.get(KEYBACKUP_URL, **headers).json() == {"blob": payload, "version": 3}
