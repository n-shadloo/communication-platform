"""No vault endpoint logs an identifier or a payload.

`caplog` installs its own handler, so the configured ScrubFilter is not applied
here. That is the point: this asserts the code never emits an id or blob in the
first place.
"""

import base64
import logging

import pytest

from core.buckets import BACKUP_BUCKETS

from .conftest import KEYBACKUP_URL, backup_blob

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)


def test_backup_paths_emit_no_identifier_or_blob(
    http, active_user, device, bearer, caplog
):
    backup_payload = backup_blob(b"S")
    headers = bearer(active_user, device)

    with caplog.at_level(logging.DEBUG):
        # A clean request logs nothing at all, so the canary is what proves the
        # capture was live rather than the assertions passing vacuously.
        logging.getLogger("test.canary").debug("canary")

        put = http.put(
            KEYBACKUP_URL,
            json={"blob": backup_payload, "version": 1},
            headers=headers,
        )
        get = http.get(KEYBACKUP_URL, headers=headers)

    assert put.status_code == 200
    assert get.status_code == 200
    assert any("canary" in record.getMessage() for record in caplog.records)

    forbidden = {
        "owner id": str(active_user.id),
        "device id": str(device.id),
        "backup blob": backup_payload,
    }
    for record in caplog.records:
        line = record.getMessage()
        for label, secret in forbidden.items():
            assert secret not in line, f"{label} leaked into a log line"


def test_no_vault_module_emits_a_log_record_at_all(
    http, active_user, device, bearer, caplog
):
    """The strongest form of invariant 6 for this app: not "the identifiers are
    scrubbed" but "there is nothing to scrub", because no logger under `vault`
    ever fires. A record here would have to be reviewed line by line before it
    could ship."""
    headers = bearer(active_user, device)

    with caplog.at_level(logging.DEBUG):
        logging.getLogger("test.canary").debug("canary")
        http.put(
            KEYBACKUP_URL,
            json={"blob": backup_blob(b"Q"), "version": 4},
            headers=headers,
        )
        http.get(KEYBACKUP_URL, headers=headers)

    assert any("canary" in record.getMessage() for record in caplog.records)
    assert [r.name for r in caplog.records if r.name.startswith("vault")] == []


def test_every_refusal_path_is_silent_too(
    http, active_user, device, bearer, register_bearer, caplog
):
    """A failure is where a logger normally appears — "bad blob from user X" is
    exactly the line an operator would add. Every refusal this route can answer
    runs here, and none of them may name the account, the device or the blob."""
    headers = bearer(active_user, device)
    stored = backup_blob(b"S")
    rejected = base64.b64encode(b"x" * (min(BACKUP_BUCKETS) - 1)).decode()
    http.put(KEYBACKUP_URL, json={"blob": stored, "version": 6}, headers=headers)

    with caplog.at_level(logging.DEBUG):
        logging.getLogger("test.canary").debug("canary")
        answers = [
            http.put(
                KEYBACKUP_URL, json={"blob": rejected, "version": 7}, headers=headers
            ).status_code,
            http.put(
                KEYBACKUP_URL, json={"blob": stored, "version": 6}, headers=headers
            ).status_code,
            http.put(
                KEYBACKUP_URL, json={"blob": stored, "version": "six"}, headers=headers
            ).status_code,
            http.get(KEYBACKUP_URL).status_code,
            http.get(KEYBACKUP_URL, headers=register_bearer(active_user)).status_code,
            http.post(KEYBACKUP_URL, json={}, headers=headers).status_code,
        ]

    assert answers == [400, 409, 400, 401, 403, 405]
    assert any("canary" in record.getMessage() for record in caplog.records)

    forbidden = {
        "owner id": str(active_user.id),
        "device id": str(device.id),
        "stored blob": stored,
        "rejected blob": rejected,
        "stored version": "6",
    }
    for record in caplog.records:
        line = record.getMessage()
        for label, secret in forbidden.items():
            assert secret not in line, f"{label} leaked into a log line"


def test_a_404_read_names_no_account(http, active_user, device, bearer, caplog):
    """The one path where the server knows an account has no backup at all — the
    state most worth writing down, and the one it must not write down."""
    headers = bearer(active_user, device)

    with caplog.at_level(logging.DEBUG):
        logging.getLogger("test.canary").debug("canary")
        missing = http.get(KEYBACKUP_URL, headers=headers)

    assert missing.status_code == 404
    assert any("canary" in record.getMessage() for record in caplog.records)
    for record in caplog.records:
        assert str(active_user.id) not in record.getMessage()
