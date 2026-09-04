"""Key backup upload/download and version monotonicity.

The backup is opaque: the server stores it and can never open it. The one rule it
does enforce is that a PUT with a version `<=` the stored one is refused, so a stale
write can never clobber the current key material.
"""

import base64

import pytest

from core.buckets import BACKUP_BUCKETS

from .conftest import KEYBACKUP_URL, backup_blob

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)


def test_get_when_absent_is_404(http, active_user, device, bearer):
    resp = http.get(KEYBACKUP_URL, headers=bearer(active_user, device))
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


def test_an_unknown_field_is_rejected(http, active_user, device, bearer):
    resp = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"R"), "version": 1, "junk": 1},
        headers=bearer(active_user, device),
    )
    assert resp.status_code == 400
    assert resp.json()["code"] == "invalid_request"


def test_put_then_get_round_trips_blob_and_version(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    blob = backup_blob(b"R")
    assert (
        http.put(
            KEYBACKUP_URL, json={"blob": blob, "version": 3}, headers=headers
        ).status_code
        == 200
    )
    got = http.get(KEYBACKUP_URL, headers=headers)
    assert got.status_code == 200
    assert got.json() == {"blob": blob, "version": 3}


def test_version_must_strictly_increase(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    assert (
        http.put(
            KEYBACKUP_URL,
            json={"blob": backup_blob(b"A"), "version": 5},
            headers=headers,
        ).status_code
        == 200
    )

    equal = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"B"), "version": 5}, headers=headers
    )
    assert equal.status_code == 409 and equal.json()["code"] == "stale_version"

    lower = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"C"), "version": 4}, headers=headers
    )
    assert lower.status_code == 409 and lower.json()["code"] == "stale_version"

    # Neither stale write clobbered the stored v5 blob.
    assert http.get(KEYBACKUP_URL, headers=headers).json() == {
        "blob": backup_blob(b"A"),
        "version": 5,
    }

    higher = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"D"), "version": 6}, headers=headers
    )
    assert higher.status_code == 200
    assert http.get(KEYBACKUP_URL, headers=headers).json() == {
        "blob": backup_blob(b"D"),
        "version": 6,
    }


def test_off_bucket_blob_is_rejected_without_echo(http, active_user, device, bearer):
    headers = bearer(active_user, device)
    bad = base64.b64encode(b"x" * (min(BACKUP_BUCKETS) - 1)).decode()
    resp = http.put(KEYBACKUP_URL, json={"blob": bad, "version": 1}, headers=headers)
    assert resp.status_code == 400 and resp.json()["code"] == "bad_bucket"
    assert bad not in resp.text


def test_a_body_above_the_route_cap_is_refused(http, active_user, device, bearer):
    """The cap is counted as the server delivers the body, so an oversized upload
    never reaches the validator that would decode it."""
    oversized = "A" * (2 * 1024 * 1024 + 1024)

    resp = http.put(
        KEYBACKUP_URL,
        json={"blob": oversized, "version": 1},
        headers=bearer(active_user, device),
    )

    assert resp.status_code == 413
    assert resp.json()["code"] == "payload_too_large"


def test_backup_is_per_user(http, active_user, device, bearer, bob, bob_device):
    http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"A"), "version": 1},
        headers=bearer(active_user, device),
    )
    # bob has uploaded nothing, so bob sees nothing; alice's backup is not shared.
    assert http.get(KEYBACKUP_URL, headers=bearer(bob, bob_device)).status_code == 404
