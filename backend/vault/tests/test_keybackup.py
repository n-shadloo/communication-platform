"""Key backup upload/download and version monotonicity.

The backup is opaque: the server stores it and can never open it. The one rule it
does enforce is that a PUT with a version `<=` the stored one is refused, so a stale
write can never clobber the current key material.
"""

import base64

import pytest

from core.buckets import BACKUP_BUCKETS
from vault.models import KeyBackup
from vault.schemas import MAX_BACKUP_CHARS

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


@pytest.mark.parametrize("size", BACKUP_BUCKETS)
def test_every_bucket_round_trips_over_http(http, active_user, device, bearer, size):
    """The normal path at every legal length, including the 1 MiB bucket, which
    is the one that has to fit under the route's own body cap."""
    headers = bearer(active_user, device)
    payload = backup_blob(b"E", size=size)

    assert (
        http.put(
            KEYBACKUP_URL, json={"blob": payload, "version": 1}, headers=headers
        ).status_code
        == 200
    )

    assert http.get(KEYBACKUP_URL, headers=headers).json() == {
        "blob": payload,
        "version": 1,
    }


def test_a_later_write_may_move_the_backup_to_another_bucket(
    http, active_user, device, bearer
):
    """A client whose key material grows past a bucket writes the next one up;
    nothing pins an account to the length it first used."""
    headers = bearer(active_user, device)
    http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"S", size=4096), "version": 1},
        headers=headers,
    )

    grown = backup_blob(b"G", size=16384)
    assert (
        http.put(
            KEYBACKUP_URL, json={"blob": grown, "version": 2}, headers=headers
        ).status_code
        == 200
    )
    assert http.get(KEYBACKUP_URL, headers=headers).json()["blob"] == grown


def test_a_replayed_write_is_refused_without_disclosing_the_stored_backup(
    http, active_user, device, bearer
):
    """Replay: the same PUT arrives twice, because the client retried a request
    whose answer it never saw. The second one is refused, and the refusal says
    only that the version must increase — a `409` that leaked the stored blob or
    the stored version would turn a retry into a read."""
    headers = bearer(active_user, device)
    body = {"blob": backup_blob(b"P"), "version": 5}
    assert http.put(KEYBACKUP_URL, json=body, headers=headers).status_code == 200

    replay = http.put(KEYBACKUP_URL, json=body, headers=headers)

    assert replay.status_code == 409
    assert replay.json() == {"code": "stale_version", "detail": "Version must increase."}
    assert body["blob"] not in replay.text
    assert "5" not in replay.text


def test_a_stale_write_from_a_far_behind_device_discloses_no_version_distance(
    http, active_user, device, bearer
):
    """The rare case: a device offline for a long time writes version 2 over a
    stored version 900. Its refusal must be byte-identical to the refusal a
    device one version behind receives, or the gap between them is readable."""
    headers = bearer(active_user, device)
    http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"N"), "version": 900}, headers=headers
    )

    far = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"F"), "version": 2}, headers=headers
    )
    near = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"F"), "version": 899}, headers=headers
    )

    assert far.status_code == near.status_code == 409
    assert far.text == near.text
    assert "900" not in far.text


def test_the_documented_recovery_from_a_409_is_refetch_and_bump(
    http, active_user, device, bearer
):
    """`vault/API.md`: on `409` the device refetches, merges and retries. The
    loop must actually terminate — the refetched version plus one is accepted."""
    headers = bearer(active_user, device)
    http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"A"), "version": 7}, headers=headers
    )

    refused = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"B"), "version": 7}, headers=headers
    )
    assert refused.status_code == 409

    current = http.get(KEYBACKUP_URL, headers=headers).json()["version"]
    merged = backup_blob(b"M")
    retry = http.put(
        KEYBACKUP_URL,
        json={"blob": merged, "version": current + 1},
        headers=headers,
    )

    assert retry.status_code == 200
    assert http.get(KEYBACKUP_URL, headers=headers).json() == {
        "blob": merged,
        "version": 8,
    }


def test_version_zero_is_writable_once_and_then_stale(http, active_user, device, bearer):
    """The low boundary of the monotonic rule, over HTTP: zero is a legal first
    version, and the moment it is stored it stops being one."""
    headers = bearer(active_user, device)

    first = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"Z"), "version": 0}, headers=headers
    )
    second = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(b"Y"), "version": 0}, headers=headers
    )

    assert first.status_code == 200
    assert second.status_code == 409
    assert http.get(KEYBACKUP_URL, headers=headers).json()["version"] == 0


def test_an_oversized_string_is_refused_by_length_before_it_is_decoded(
    http, active_user, device, bearer
):
    """The split `vault/schemas.py` documents, seen from outside: the same
    unusable value answers `invalid_request` when it is too long and `bad_bucket`
    when it is short enough to decode. The first code is the proof that an
    arbitrarily long string never reaches `b64decode`."""
    headers = bearer(active_user, device)
    junk = "!" * 8

    too_long = http.put(
        KEYBACKUP_URL,
        json={"blob": "!" * (MAX_BACKUP_CHARS + 1), "version": 1},
        headers=headers,
    )
    short_enough = http.put(
        KEYBACKUP_URL, json={"blob": junk, "version": 1}, headers=headers
    )

    assert too_long.status_code == short_enough.status_code == 400
    assert too_long.json()["code"] == "invalid_request"
    assert short_enough.json()["code"] == "bad_bucket"


@pytest.mark.parametrize(
    "size",
    [
        pytest.param(min(BACKUP_BUCKETS) - 1, id="one under the smallest"),
        pytest.param(min(BACKUP_BUCKETS) + 1, id="one over the smallest"),
        pytest.param(8192, id="between two buckets"),
        pytest.param(max(BACKUP_BUCKETS) - 1, id="one under the largest"),
    ],
)
def test_an_off_bucket_length_is_refused_at_every_edge(
    http, active_user, device, bearer, size
):
    headers = bearer(active_user, device)
    blob = base64.b64encode(b"x" * size).decode()

    response = http.put(KEYBACKUP_URL, json={"blob": blob, "version": 1}, headers=headers)

    assert response.status_code == 400
    assert response.json()["code"] == "bad_bucket"
    assert http.get(KEYBACKUP_URL, headers=headers).status_code == 404


def test_two_backups_in_one_bucket_are_indistinguishable_by_length(
    http, active_user, device, bearer, bob, bob_device
):
    """Invariant 4 from the reader's side: the bucket is the only length there
    is. Two accounts whose real key material differs in size pad to the same
    bucket, and every byte count an observer can reach — the stored column and
    the read response — is identical for both."""
    padded_short = base64.b64encode(b"k" + bytes(4095)).decode()
    padded_long = base64.b64encode(b"k" * 4000 + bytes(96)).decode()

    for headers, blob in (
        (bearer(active_user, device), padded_short),
        (bearer(bob, bob_device), padded_long),
    ):
        assert (
            http.put(
                KEYBACKUP_URL, json={"blob": blob, "version": 1}, headers=headers
            ).status_code
            == 200
        )

    mine = http.get(KEYBACKUP_URL, headers=bearer(active_user, device))
    theirs = http.get(KEYBACKUP_URL, headers=bearer(bob, bob_device))
    assert len(mine.content) == len(theirs.content)
    assert {len(bytes(row.blob)) for row in KeyBackup.objects.all()} == {4096}


def test_the_largest_version_the_column_can_hold_is_accepted(
    http, active_user, device, bearer
):
    """The top boundary of the version space. `version` is a
    `PositiveIntegerField`, so 2147483647 is the last value the column can hold,
    and a client that has bumped that far must still be able to write it.

    One above this is where the schema's `ge=0` bound and the column's range stop
    agreeing: the route has no upper bound of its own, so the value reaches
    PostgreSQL and the request ends as a `500` rather than as a refusal.
    """
    headers = bearer(active_user, device)
    highest = 2**31 - 1

    response = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"T"), "version": highest},
        headers=headers,
    )

    assert response.status_code == 200
    assert http.get(KEYBACKUP_URL, headers=headers).json()["version"] == highest
