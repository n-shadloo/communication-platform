"""The HTTP surface of `/me/keybackup`, hostile input included.

Two routes on one path, and the whole malformed-input matrix against the writer:
a body that is not an object, a field of the wrong type, an oversized string, a
string that is not base64, a length that is not a bucket, a duplicated key, an
unknown field and an embedded control character. Every one of them must be a
`400` carrying the envelope — never a `500`, and never an echo of what was sent,
because the thing being sent is the account's key material.
"""

import base64
import json

import pytest

from accounts.schemas import MAX_VERSION_INT
from core.buckets import BACKUP_BUCKETS
from vault.models import KeyBackup

from .conftest import KEYBACKUP_URL, backup_blob

# transaction=True because the ORM bracket of `api.orm.run_unit` closes the
# connection around every unit of work, which under a wrapping test transaction
# would sever the connection the test itself holds.
pytestmark = pytest.mark.django_db(transaction=True)

ENVELOPE_KEYS = {"code", "detail"}
SMALLEST = min(BACKUP_BUCKETS)
# The base64 bound `vault/schemas.py` sets; a string past it is refused by length
# before anything tries to decode it.
MAX_BLOB_CHARS = 1398112


def json_headers(headers):
    return {**headers, "Content-Type": "application/json"}


def malformed_bodies():
    """Every shape of bad body, and the code the surface answers it with."""
    good = backup_blob()
    return {
        "an array body": ([1, 2], "invalid_request"),
        "a string body": ("hello", "invalid_request"),
        "a number body": (5, "invalid_request"),
        "a null body": (None, "invalid_request"),
        "a version sent as a string": ({"blob": good, "version": "5"}, "invalid_request"),
        "a version sent as a float": ({"blob": good, "version": 5.0}, "invalid_request"),
        "a version sent as a bool": ({"blob": good, "version": True}, "invalid_request"),
        "a negative version": ({"blob": good, "version": -1}, "invalid_request"),
        # `version` lands in a 32-bit column. Without the ceiling
        # `accounts.schemas.BlobIn` sets, this reached the column as psycopg's
        # DataError — a 500 on a route whose whole job is filtering input.
        "a version past the column ceiling": (
            {"blob": good, "version": MAX_VERSION_INT + 1},
            "invalid_request",
        ),
        "a blob sent as a number": ({"blob": 5, "version": 1}, "invalid_request"),
        "a blob sent as null": ({"blob": None, "version": 1}, "invalid_request"),
        "a blob sent as an object": ({"blob": {}, "version": 1}, "invalid_request"),
        "a blob sent as an array": ({"blob": [], "version": 1}, "invalid_request"),
        "a missing blob": ({"version": 1}, "invalid_request"),
        "a missing version": ({"blob": good}, "invalid_request"),
        "an unknown field": (
            {"blob": good, "version": 1, "recovery": "x"},
            "invalid_request",
        ),
        "an oversized blob string": (
            {"blob": "A" * (MAX_BLOB_CHARS + 1), "version": 1},
            "invalid_request",
        ),
        "a blob outside the base64 alphabet": (
            {"blob": "!!!!", "version": 1},
            "bad_bucket",
        ),
        "a blob with an embedded newline": (
            {"blob": "QUFB\nQUFB", "version": 1},
            "bad_bucket",
        ),
        "a blob with an embedded nul": (
            {"blob": "QUFB\x00QUFB", "version": 1},
            "bad_bucket",
        ),
        "a blob with an embedded bell": (
            {"blob": "QUFB\x07QUFB", "version": 1},
            "bad_bucket",
        ),
        "an empty blob": ({"blob": "", "version": 1}, "bad_bucket"),
        "a blob one byte under a bucket": (
            {"blob": base64.b64encode(b"u" * (SMALLEST - 1)).decode(), "version": 1},
            "bad_bucket",
        ),
        "a blob one byte over a bucket": (
            {"blob": base64.b64encode(b"o" * (SMALLEST + 1)).decode(), "version": 1},
            "bad_bucket",
        ),
        "a blob between two buckets": (
            {"blob": base64.b64encode(b"m" * 8192).decode(), "version": 1},
            "bad_bucket",
        ),
    }


@pytest.mark.parametrize("case", list(malformed_bodies()))
def test_a_malformed_write_is_a_described_400(http, active_user, device, bearer, case):
    body, expected_code = malformed_bodies()[case]

    response = http.put(KEYBACKUP_URL, json=body, headers=bearer(active_user, device))

    assert response.status_code == 400, f"{case} answered {response.status_code}"
    assert set(response.json()) == ENVELOPE_KEYS
    assert response.json()["code"] == expected_code


@pytest.mark.parametrize("case", list(malformed_bodies()))
def test_a_malformed_write_stores_nothing_and_echoes_nothing(
    http, active_user, device, bearer, case
):
    """The refusal must not become an oracle. `detail` may name the field that
    failed; it may never carry the value, which for this route is key material."""
    body, _ = malformed_bodies()[case]
    sent = json.dumps(body)

    response = http.put(KEYBACKUP_URL, json=body, headers=bearer(active_user, device))

    assert KeyBackup.objects.count() == 0
    if isinstance(body, dict) and isinstance(body.get("blob"), str) and body["blob"]:
        assert body["blob"] not in response.text
    assert sent not in response.text


def test_a_body_that_is_not_json_at_all_is_a_400(http, active_user, device, bearer):
    response = http.put(
        KEYBACKUP_URL,
        content=b"{not json",
        headers=json_headers(bearer(active_user, device)),
    )

    assert response.status_code == 400
    assert response.json()["code"] == "invalid_request"


def test_a_duplicated_key_settles_on_the_last_value_rather_than_failing(
    http, active_user, device, bearer
):
    """The rare case: JSON permits a key twice and the two decoders in front of
    this route could disagree about which wins. One does win, deterministically,
    and the stored row proves which — a `500` from a disagreement would be the
    defect."""
    body = '{"blob": "%s", "version": 1, "version": 2}' % backup_blob(b"D")

    response = http.put(
        KEYBACKUP_URL,
        content=body.encode(),
        headers=json_headers(bearer(active_user, device)),
    )

    assert response.status_code == 200
    assert KeyBackup.objects.get(user_id=active_user.id).version == 2


def test_a_duplicated_blob_key_stores_the_last_blob(http, active_user, device, bearer):
    body = '{"blob": "%s", "blob": "%s", "version": 1}' % (
        backup_blob(b"1"),
        backup_blob(b"2"),
    )

    response = http.put(
        KEYBACKUP_URL,
        content=body.encode(),
        headers=json_headers(bearer(active_user, device)),
    )

    assert response.status_code == 200
    stored = bytes(KeyBackup.objects.get(user_id=active_user.id).blob)
    assert stored == base64.b64decode(backup_blob(b"2"))


def test_the_write_answers_200_with_an_empty_body(http, active_user, device, bearer):
    """The route declares `Response` rather than a model, so a successful write
    tells the client nothing at all — not even the version it just stored."""
    response = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(), "version": 1},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200
    assert response.content == b""
    assert response.headers["content-length"] == "0"


def test_the_read_answers_exactly_the_two_documented_fields(
    http, active_user, device, bearer
):
    headers = bearer(active_user, device)
    http.put(KEYBACKUP_URL, json={"blob": backup_blob(), "version": 1}, headers=headers)

    body = http.get(KEYBACKUP_URL, headers=headers).json()

    assert set(body) == {"blob", "version"}


@pytest.mark.parametrize("method", ["POST", "DELETE", "PATCH"])
def test_a_method_the_path_does_not_serve_is_405(
    http, active_user, device, bearer, method
):
    """There is no delete and no partial update: a backup is replaced whole or
    left alone."""
    response = http.request(method, KEYBACKUP_URL, headers=bearer(active_user, device))

    assert response.status_code == 405
    assert response.json()["code"] == "method_not_allowed"


@pytest.mark.parametrize(
    "path",
    ["/api/v1/me/keybackup/history", "/api/v1/me/keybackup/1", "/api/v1/me/keybackups"],
)
def test_no_neighbouring_path_exists(http, active_user, device, bearer, path):
    """The vault serves one path. A versions or history path answering anything
    but a routing miss would be a second copy of the key material."""
    response = http.get(path, headers=bearer(active_user, device))

    assert response.status_code == 404
    assert response.json()["code"] == "not_found"


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_a_request_with_no_token_is_401(http, method):
    response = http.request(
        method, KEYBACKUP_URL, json={"blob": backup_blob(), "version": 1}
    )

    assert response.status_code == 401
    assert response.json()["code"] == "unauthenticated"


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_a_token_that_is_not_a_token_is_401(http, method):
    response = http.request(
        method,
        KEYBACKUP_URL,
        json={"blob": backup_blob(), "version": 1},
        headers={"Authorization": "Bearer not-a-token"},
    )

    assert response.status_code == 401
    assert response.json()["code"] == "invalid_token"


def test_authentication_is_settled_before_the_body_is_parsed(http):
    """Ordering, and the rare case that exposes it: a malformed body from an
    anonymous caller must answer `401`, not `400`. A surface that validated
    first would tell an unauthenticated caller the shape of the body."""
    response = http.put(KEYBACKUP_URL, json={"blob": [], "version": "nope"})

    assert response.status_code == 401


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_every_answer_carries_the_security_headers(
    http, active_user, device, bearer, method
):
    """`no-store` above all: the read carries the account's wrapped private keys,
    and a cache that kept it would be a copy of the vault outside the vault."""
    response = http.request(
        method,
        KEYBACKUP_URL,
        json={"blob": backup_blob(), "version": 1},
        headers=bearer(active_user, device),
    )

    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["referrer-policy"] == "no-referrer"


def test_the_read_and_the_write_share_one_rate_limit_counter(
    http, active_user, device, bearer, settings
):
    """Both routes declare the `accounts` scope, so a client cannot get twice the
    budget by alternating verbs. The rate is lowered through settings rather than
    by sending 120 requests."""
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "accounts": "2/min"}
    headers = bearer(active_user, device)

    first = http.put(
        KEYBACKUP_URL, json={"blob": backup_blob(), "version": 1}, headers=headers
    )
    second = http.get(KEYBACKUP_URL, headers=headers)
    third = http.get(KEYBACKUP_URL, headers=headers)

    assert (first.status_code, second.status_code) == (200, 200)
    assert third.status_code == 429
    assert third.json()["code"] == "throttled"
    assert int(third.headers["Retry-After"]) > 0


def test_the_version_column_takes_its_largest_value_and_refuses_one_past_it(
    http, active_user, device, bearer
):
    """The boundary, from both sides. `version` is a 32-bit column, so the schema
    bounds it rather than letting the column raise: the ceiling itself stores, and
    one past it is a refusal rather than the server error this used to be."""
    headers = bearer(active_user, device)

    at_ceiling = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"C"), "version": MAX_VERSION_INT},
        headers=headers,
    )
    past_it = http.put(
        KEYBACKUP_URL,
        json={"blob": backup_blob(b"D"), "version": MAX_VERSION_INT + 1},
        headers=headers,
    )

    assert at_ceiling.status_code == 200
    assert past_it.status_code == 400
    assert past_it.json()["code"] == "invalid_request"
    assert KeyBackup.objects.get(user_id=active_user.id).version == MAX_VERSION_INT
