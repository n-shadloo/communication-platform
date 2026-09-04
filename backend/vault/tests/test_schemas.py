"""The key-backup request and response models, exercised without a request.

`vault/schemas.py` splits one job across two guards, and the comment above
`MAX_BACKUP_CHARS` says which half does what: the `max_length` bound exists so an
arbitrarily long string never reaches `b64decode`, and the *exact* length rule is
`decode_blob_or_400`'s. The two halves answer with different exceptions —
`ValidationError` becomes `400 invalid_request`, `BadBucket` becomes `400
bad_bucket` — so the exception type is the observable that proves which guard
refused a value, and therefore also proves the order they run in.
"""

import base64

import pytest
from hypothesis import given
from hypothesis import strategies as st
from pydantic import ValidationError

from core.buckets import BACKUP_BUCKETS
from core.fields import BadBucket
from vault.schemas import MAX_BACKUP_CHARS, KeyBackupIn, KeyBackupOut

# The bound `vault/API.md` publishes to the client. Written out rather than
# recomputed, so a change to the formula has to be a change to the document too.
DOCUMENTED_MAX_CHARS = 1398112


def b64_of(size, filler=b"B"):
    return base64.b64encode((filler * size)[:size]).decode()


def test_the_length_bound_is_the_one_the_document_publishes():
    assert MAX_BACKUP_CHARS == DOCUMENTED_MAX_CHARS


def test_the_bound_admits_the_largest_bucket_with_headroom_to_spare():
    """The normal path of the bound: the biggest legal upload must fit under it,
    or the guard meant to stop absurd strings would reject legal ones."""
    largest = b64_of(max(BACKUP_BUCKETS))

    assert len(largest) <= MAX_BACKUP_CHARS
    assert KeyBackupIn(blob=largest, version=1).raw == b"B" * max(BACKUP_BUCKETS)


@pytest.mark.parametrize("size", BACKUP_BUCKETS)
def test_every_bucket_decodes_to_its_exact_byte_count(size):
    model = KeyBackupIn(blob=b64_of(size, b"K"), version=7)

    assert len(model.raw) == size
    assert model.version == 7


@pytest.mark.parametrize("delta", [-1, 1])
def test_a_blob_one_byte_off_a_bucket_is_a_bad_bucket(delta):
    """The boundary the exact-length half owns."""
    with pytest.raises(BadBucket):
        KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS) + delta), version=1)


def test_a_string_past_the_bound_is_refused_by_length_not_by_the_decoder():
    """The first half of the split. The value is not base64 at all, so a decoder
    that saw it would raise `BadBucket`; `ValidationError` is the proof that the
    length guard refused it first and the decoder never ran on it."""
    with pytest.raises(ValidationError) as caught:
        KeyBackupIn(blob="!" * (MAX_BACKUP_CHARS + 1), version=1)

    assert caught.value.errors()[0]["loc"] == ("blob",)
    assert "at most" in caught.value.errors()[0]["msg"]


def test_a_string_at_the_bound_reaches_the_decoder_and_is_refused_by_it():
    """The second half, and the exact boundary between them: one character
    shorter than the case above, the same guard no longer applies, the decoder
    runs, and the refusal changes shape from `ValidationError` to `BadBucket`."""
    at_the_bound = "A" * MAX_BACKUP_CHARS

    with pytest.raises(BadBucket):
        KeyBackupIn(blob=at_the_bound, version=1)


def test_a_gigantic_well_formed_string_still_never_reaches_the_decoder():
    """The rare case the bound exists for: valid base64 alphabet, so the decoder
    would happily allocate megabytes before measuring. The length guard answers
    instead."""
    with pytest.raises(ValidationError):
        KeyBackupIn(blob="A" * (MAX_BACKUP_CHARS + 4096), version=1)


@pytest.mark.parametrize(
    "blob",
    [
        pytest.param("", id="empty"),
        pytest.param("!!!!", id="outside the alphabet"),
        pytest.param("QUFB QUFB", id="embedded space"),
        pytest.param("QUFB\nQUFB", id="embedded newline"),
        pytest.param("QUFB\x00QUFB", id="embedded nul"),
        pytest.param("QUFBQUFB=", id="broken padding"),
    ],
)
def test_a_blob_that_is_not_clean_base64_is_a_bad_bucket(blob):
    with pytest.raises(BadBucket):
        KeyBackupIn(blob=blob, version=1)


@pytest.mark.parametrize(
    "version",
    [pytest.param("1", id="string"), pytest.param(1.0, id="float"), True],
)
def test_a_version_of_the_wrong_type_is_refused_rather_than_converted(version):
    """Strict mode, inherited from `RequestModel`: `"5"` is not 5 here."""
    with pytest.raises(ValidationError) as caught:
        KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS)), version=version)

    assert caught.value.errors()[0]["loc"] == ("version",)


def test_a_negative_version_is_refused():
    with pytest.raises(ValidationError) as caught:
        KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS)), version=-1)

    assert "greater than or equal to 0" in caught.value.errors()[0]["msg"]


def test_version_zero_is_a_legal_first_version():
    """The low boundary: `ge=0`, not `gt=0`, so a client that starts counting at
    zero is not turned away."""
    assert KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS)), version=0).version == 0


def test_an_unknown_field_is_refused_rather_than_dropped():
    with pytest.raises(ValidationError) as caught:
        KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS)), version=1, recovery="hunter2")

    assert caught.value.errors()[0]["loc"] == ("recovery",)


def test_a_missing_field_names_itself():
    with pytest.raises(ValidationError) as caught:
        KeyBackupIn(blob=b64_of(min(BACKUP_BUCKETS)))

    assert caught.value.errors()[0]["loc"] == ("version",)


def test_the_models_carry_exactly_the_two_documented_fields():
    assert set(KeyBackupIn.model_fields) == {"blob", "version"}
    assert set(KeyBackupOut.model_fields) == {"blob", "version"}


def test_the_response_model_serialises_the_two_fields_and_nothing_else():
    out = KeyBackupOut(blob="QUFB", version=4)

    assert out.model_dump() == {"blob": "QUFB", "version": 4}


@given(payload=st.binary(min_size=0, max_size=96))
def test_any_bytes_padded_to_a_bucket_survive_the_model_byte_identical(payload):
    """The blind-relay property at the parsing boundary: the model hands the unit
    of work the exact bytes the client encoded, whatever they are. Padded to the
    smallest bucket, because the length rule is the only thing the server reads."""
    size = min(BACKUP_BUCKETS)
    raw = (payload + bytes(size))[:size]

    assert KeyBackupIn(blob=base64.b64encode(raw).decode(), version=1).raw == raw
