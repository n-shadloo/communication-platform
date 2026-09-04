"""The headline restore flow, post-history: the key backup only.

Device 1 uploads the recovery-protected key backup (cross-signing private keys and
identity material); a brand-new device 2 for the same user reads it back
byte-identical. That is everything a new device gets from the server — message
history transfers client-to-client from an existing device and never appears here.
"""

import pytest

from .conftest import KEYBACKUP_URL, backup_blob, make_device

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)


def test_a_new_device_restores_the_key_backup_byte_identical(
    http, active_user, device, bearer
):
    device1 = bearer(active_user, device)
    backup_payload = backup_blob(b"K", size=16384)

    assert (
        http.put(
            KEYBACKUP_URL,
            json={"blob": backup_payload, "version": 1},
            headers=device1,
        ).status_code
        == 200
    )

    # A brand-new device for the same account, with its own full-scope token.
    device2 = bearer(active_user, make_device(active_user, registration_id=2))
    assert http.get(KEYBACKUP_URL, headers=device2).json() == {
        "blob": backup_payload,
        "version": 1,
    }


def test_backups_are_scoped_to_their_owner(
    http, active_user, device, bearer, bob, bob_device
):
    http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"A"), "version": 1},
        headers=bearer(active_user, device),
    )

    theirs = http.get(KEYBACKUP_URL, headers=bearer(bob, bob_device))

    assert theirs.status_code == 404
