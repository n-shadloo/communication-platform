"""The headline restore flow, post-history: the key backup only.

Device 1 uploads the recovery-protected key backup (cross-signing private keys and
identity material); a brand-new device 2 for the same user reads it back
byte-identical. That is everything a new device gets from the server — message
history transfers client-to-client from an existing device and never appears here.
"""

import pytest

from .conftest import KEYBACKUP_URL, backup_blob, make_device

pytestmark = pytest.mark.django_db


def test_a_new_device_restores_the_key_backup_byte_identical(
    api, active_user, device, auth_headers
):
    device1 = auth_headers(active_user, device)
    backup_payload = backup_blob(b"K", size=16384)

    assert (
        api.put(
            KEYBACKUP_URL,
            {"blob": backup_payload, "version": 1},
            format="json",
            **device1,
        ).status_code
        == 200
    )

    # A brand-new device for the same account, with its own full-scope token.
    device2 = auth_headers(active_user, make_device(active_user, registration_id=2))
    assert api.get(KEYBACKUP_URL, **device2).json() == {
        "blob": backup_payload,
        "version": 1,
    }


def test_backups_are_scoped_to_their_owner(
    api, active_user, device, auth_headers, bob, bob_device
):
    api.put(
        KEYBACKUP_URL,
        {"blob": backup_blob(b"A"), "version": 1},
        format="json",
        **auth_headers(active_user, device),
    )

    theirs = api.get(KEYBACKUP_URL, **auth_headers(bob, bob_device))

    assert theirs.status_code == 404
