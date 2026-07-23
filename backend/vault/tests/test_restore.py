"""The headline restore flow.

Device 1 uploads a key backup and 250 history records across 3 batches; a brand-new
device 2 for the same user reads every record via keyset paging in order, and reads
the backup blob back byte-identical. History is owner-scoped, so a new device sees
the log without anything device-specific being shared.
"""
import pytest

from .conftest import (HISTORY_URL, KEYBACKUP_URL, backup_blob, make_device,
                       uniq_history_blob)

pytestmark = pytest.mark.django_db


def test_new_device_restores_history_in_order_and_backup_byte_identical(
        api, active_user, device, auth_headers):
    device1 = auth_headers(active_user, device)

    backup_payload = backup_blob(b"K", size=16384)
    assert api.put(KEYBACKUP_URL, {"blob": backup_payload, "version": 1},
                   format="json", **device1).status_code == 200

    idx = 0
    for batch in (100, 100, 50):
        blobs = [uniq_history_blob(idx + k) for k in range(batch)]
        resp = api.post(HISTORY_URL, {"records": [{"blob": b} for b in blobs]},
                        format="json", **device1)
        assert resp.status_code == 201
        assert resp.json() == {"first_seq": idx, "last_seq": idx + batch - 1}
        idx += batch
    assert idx == 250

    # A brand-new device for the same account, with its own full-scope token.
    device2 = auth_headers(active_user, make_device(active_user, registration_id=2))

    seen, after = [], -1
    while True:
        page = api.get(f"{HISTORY_URL}?after={after}&limit=100", **device2).json()
        seen.extend(page["records"])
        if not page["has_more"]:
            break
        after = seen[-1]["seq"]

    assert [r["seq"] for r in seen] == list(range(250))
    assert [r["blob"] for r in seen] == [uniq_history_blob(i) for i in range(250)]

    # The backup comes back byte-identical to what device 1 uploaded.
    assert api.get(KEYBACKUP_URL, **device2).json() == {"blob": backup_payload, "version": 1}
