"""No vault endpoint logs an identifier or a payload.

`caplog` installs its own handler, so the configured ScrubFilter is not applied
here. That is the point: this asserts the code never emits an id or blob in the
first place.
"""

import logging

import pytest

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
