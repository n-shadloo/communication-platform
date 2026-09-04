"""The two units of work behind the route, driven without a request.

Called directly rather than through HTTP, so what is asserted here is the unit's
own contract: the row it leaves, the bytes it stores, and the `ApiError` it
raises. The route's rendering of those errors is `vault/tests/test_routes.py`.
"""

import base64

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st

from api.errors import ApiError
from core.buckets import BACKUP_BUCKETS
from vault import services
from vault.models import KeyBackup

from .conftest import backup_blob

pytestmark = pytest.mark.django_db(transaction=True)

SMALLEST = min(BACKUP_BUCKETS)


def raw(filler=b"S", size=SMALLEST):
    return (filler * size)[:size]


def test_reading_an_account_with_no_backup_raises_the_documented_404(active_user):
    with pytest.raises(ApiError) as caught:
        services.read(active_user.id)

    assert caught.value.status_code == 404
    assert caught.value.code == "not_found"
    assert caught.value.detail == "No key backup yet."


def test_a_first_write_creates_exactly_one_row_carrying_its_bytes(active_user):
    services.write(active_user.id, raw(b"A"), 1)

    rows = KeyBackup.objects.filter(user_id=active_user.id)
    assert rows.count() == 1
    assert bytes(rows.get().blob) == raw(b"A")
    assert rows.get().version == 1


def test_reading_back_returns_the_blob_base64_encoded_and_the_version(active_user):
    services.write(active_user.id, raw(b"R"), 2)

    assert services.read(active_user.id) == {
        "blob": base64.b64encode(raw(b"R")).decode(),
        "version": 2,
    }


def test_version_zero_is_accepted_as_a_first_write(active_user):
    """The boundary of the monotonic rule: with nothing stored there is no
    version to be greater than, so the check is skipped rather than compared
    against the field's `default=0`."""
    services.write(active_user.id, raw(b"Z"), 0)

    assert services.read(active_user.id)["version"] == 0


def test_a_second_write_at_version_zero_is_stale(active_user):
    """The other side of that boundary: once zero is *stored*, zero no longer
    increases, so the same call that was legal a moment ago is refused."""
    services.write(active_user.id, raw(b"Z"), 0)

    with pytest.raises(ApiError) as caught:
        services.write(active_user.id, raw(b"Y"), 0)

    assert caught.value.status_code == 409


def test_a_higher_version_replaces_the_blob_in_place(active_user):
    services.write(active_user.id, raw(b"1"), 1)
    services.write(active_user.id, raw(b"2"), 9)

    assert KeyBackup.objects.filter(user_id=active_user.id).count() == 1
    assert services.read(active_user.id) == {
        "blob": base64.b64encode(raw(b"2")).decode(),
        "version": 9,
    }


@pytest.mark.parametrize("version", [4, 5], ids=["lower", "equal"])
def test_a_write_that_does_not_increase_the_version_is_refused(active_user, version):
    services.write(active_user.id, raw(b"K"), 5)

    with pytest.raises(ApiError) as caught:
        services.write(active_user.id, raw(b"X"), version)

    assert caught.value.status_code == 409
    assert caught.value.code == "stale_version"


def test_a_refused_write_leaves_the_stored_row_untouched(active_user):
    """The unit opens a transaction before it reads the version, so the refusal
    is a rollback, not a partial write."""
    services.write(active_user.id, raw(b"K"), 5)

    with pytest.raises(ApiError):
        services.write(active_user.id, raw(b"X"), 5)

    stored = KeyBackup.objects.get(user_id=active_user.id)
    assert bytes(stored.blob) == raw(b"K")
    assert stored.version == 5


def test_the_refusal_discloses_neither_the_stored_version_nor_the_stored_blob(
    active_user,
):
    """A stale writer learns that it is stale and nothing else. Anything of the
    current row in the message would hand an attacker holding one device's token
    a read the 409 was refusing to perform."""
    stored = raw(b"Q")
    services.write(active_user.id, stored, 5)

    with pytest.raises(ApiError) as caught:
        services.write(active_user.id, raw(b"X"), 3)

    message = f"{caught.value.detail} {caught.value.code} {caught.value.args}"
    assert "5" not in message
    assert base64.b64encode(stored).decode() not in message
    assert caught.value.detail == "Version must increase."


def test_one_accounts_backup_is_invisible_to_another(active_user, bob):
    services.write(active_user.id, raw(b"A"), 1)

    with pytest.raises(ApiError) as caught:
        services.read(bob.id)

    assert caught.value.status_code == 404


def test_two_accounts_keep_independent_rows_and_versions(active_user, bob):
    services.write(active_user.id, raw(b"A"), 1)
    services.write(bob.id, raw(b"B"), 400)

    assert services.read(active_user.id)["version"] == 1
    assert services.read(bob.id)["blob"] == base64.b64encode(raw(b"B")).decode()
    assert KeyBackup.objects.count() == 2


@pytest.mark.parametrize("size", BACKUP_BUCKETS)
def test_every_bucket_size_round_trips_byte_identical(active_user, size):
    payload = raw(b"P", size)

    services.write(active_user.id, payload, 1)

    assert base64.b64decode(services.read(active_user.id)["blob"]) == payload


def test_the_encoded_blob_matches_what_the_conftest_helper_uploads(active_user):
    """Ties the unit's encoding to the exact string the HTTP tests send, so the
    two layers cannot drift into different base64 dialects."""
    services.write(active_user.id, raw(b"B"), 1)

    assert services.read(active_user.id)["blob"] == backup_blob(b"B")


@settings(max_examples=25)
@given(payload=st.binary(min_size=0, max_size=128))
def test_whatever_bytes_are_written_come_back_unchanged(active_user, payload):
    """The blind-relay property at the storage boundary: the server neither
    parses nor normalises what it holds. A round trip through PostgreSQL's
    `bytea` and back through base64 must be the identity function.

    Each example writes one version above whatever is stored, because the row
    survives from one example to the next — hypothesis does not roll the database
    back between them.
    """
    current = KeyBackup.objects.filter(user_id=active_user.id).first()
    stored = (payload + bytes(SMALLEST))[:SMALLEST]

    services.write(active_user.id, stored, 1 if current is None else current.version + 1)

    assert base64.b64decode(services.read(active_user.id)["blob"]) == stored
