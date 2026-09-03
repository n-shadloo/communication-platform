"""Key backup upload/download and version monotonicity.

The backup is opaque: the server stores it and can never open it. The one rule it
does enforce is that a PUT with a version `<=` the stored one is refused, so a stale
write can never clobber the current key material.
"""

import base64

import pytest

from core.buckets import BACKUP_BUCKETS

from .conftest import KEYBACKUP_URL, backup_blob

pytestmark = pytest.mark.django_db


def test_get_when_absent_is_404(api, active_user, device, auth_headers):
    resp = api.get(KEYBACKUP_URL, **auth_headers(active_user, device))
    assert resp.status_code == 404
    assert resp.json()["code"] == "not_found"


def test_an_unknown_field_is_rejected(api, active_user, device, auth_headers):
    resp = api.put(
        KEYBACKUP_URL,
        {"blob": backup_blob(b"R"), "version": 1, "junk": 1},
        format="json",
        **auth_headers(active_user, device),
    )
    assert resp.status_code == 400


def test_put_then_get_round_trips_blob_and_version(
    api, active_user, device, auth_headers
):
    headers = auth_headers(active_user, device)
    blob = backup_blob(b"R")
    assert (
        api.put(
            KEYBACKUP_URL, {"blob": blob, "version": 3}, format="json", **headers
        ).status_code
        == 200
    )
    got = api.get(KEYBACKUP_URL, **headers)
    assert got.status_code == 200
    assert got.json() == {"blob": blob, "version": 3}


def test_version_must_strictly_increase(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    assert (
        api.put(
            KEYBACKUP_URL,
            {"blob": backup_blob(b"A"), "version": 5},
            format="json",
            **headers,
        ).status_code
        == 200
    )

    equal = api.put(
        KEYBACKUP_URL, {"blob": backup_blob(b"B"), "version": 5}, format="json", **headers
    )
    assert equal.status_code == 409 and equal.json()["code"] == "stale_version"

    lower = api.put(
        KEYBACKUP_URL, {"blob": backup_blob(b"C"), "version": 4}, format="json", **headers
    )
    assert lower.status_code == 409 and lower.json()["code"] == "stale_version"

    # Neither stale write clobbered the stored v5 blob.
    assert api.get(KEYBACKUP_URL, **headers).json() == {
        "blob": backup_blob(b"A"),
        "version": 5,
    }

    higher = api.put(
        KEYBACKUP_URL, {"blob": backup_blob(b"D"), "version": 6}, format="json", **headers
    )
    assert higher.status_code == 200
    assert api.get(KEYBACKUP_URL, **headers).json() == {
        "blob": backup_blob(b"D"),
        "version": 6,
    }


def test_off_bucket_blob_is_rejected_without_echo(api, active_user, device, auth_headers):
    headers = auth_headers(active_user, device)
    bad = base64.b64encode(b"x" * (min(BACKUP_BUCKETS) - 1)).decode()
    resp = api.put(KEYBACKUP_URL, {"blob": bad, "version": 1}, format="json", **headers)
    assert resp.status_code == 400 and resp.json()["code"] == "bad_bucket"
    assert bad not in resp.content.decode()


def test_backup_is_per_user(api, active_user, device, auth_headers, bob, bob_device):
    api.put(
        KEYBACKUP_URL,
        {"blob": backup_blob(b"A"), "version": 1},
        format="json",
        **auth_headers(active_user, device),
    )
    # bob has uploaded nothing, so bob sees nothing; alice's backup is not shared.
    assert api.get(KEYBACKUP_URL, **auth_headers(bob, bob_device)).status_code == 404
