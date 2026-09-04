"""What every room route does with input it cannot use.

One rule holds across the whole surface: a request the server cannot act on is
answered with the documented status carrying the `{code, detail}` envelope, and
never with a `500` and never with an echo of what was sent. Four routes read
client input here — a body on two of them and a capability id in the path on
three — so the matrix below is a matrix rather than a spot check.

The echo half is not decoration. `name_blob` is the encrypted room name and
`room_id` is the capability that opens the room, so a refusal that quoted either
back would turn the error handler into the oracle the rest of the design exists
to avoid. Pydantic names at most the single character that failed a UUID parse,
which is why the path cases below are two characters or longer.

`voicerooms/tests/test_rooms_api.py` owns the successful shapes and the scope
rules; this file owns the refusals.
"""

import base64
import json
import uuid
from urllib.parse import quote, unquote

import pytest
from hypothesis import example, given, settings
from hypothesis import strategies as st

from core.buckets import NAME_BUCKETS
from voicerooms.models import Room
from voicerooms.schemas import MAX_NAME_CHARS

from .conftest import NAME_LEN, ROOMS_URL, envelope, name_blob_b64

# transaction=True because every route runs its unit of work through the ORM
# bracket of `api.orm.run_unit`, which closes the connection a wrapping test
# transaction would need.
pytestmark = pytest.mark.django_db(transaction=True)

# The JSON body cap of this route class, from `api/app.py`.
BODY_CAP_BYTES = 16 * 1024

# The largest byte count whose base64 still fits under `MAX_NAME_CHARS`.
LARGEST_DECODABLE = 3 * (MAX_NAME_CHARS // 4)

MISSING = uuid.uuid4()

# A path segment and the answer the surface documents for it. Every one of them
# is a client defect rather than a missing room, so every one is `400
# invalid_request` — the capability id never reaches the lookup.
BAD_PATH_SEGMENTS = {
    "a segment that is not a uuid": "not-a-uuid",
    "a bare integer": "77",
    "a uuid with a trailing space": quote(f"{MISSING} ", safe=""),
    "a uuid carrying a nul byte": quote(f"{str(MISSING)[:-1]}\x00", safe=""),
    "a uuid carrying an escape character": quote(f"{str(MISSING)[:-1]}\x1b", safe=""),
    "a uuid carrying a newline": quote(f"{MISSING}\n", safe=""),
    "a uuid with one character too few": str(MISSING)[:-1],
    "an oversized segment": "a" * 4000,
    "a quoted sql fragment": quote("1' OR '1'='1", safe=""),
    "a template expression": quote("{{7*7}}", safe=""),
}


# Spellings of a real capability id that Python's own UUID parser accepts. They
# are the same 128 bits, so they name the same room and grant nothing extra.
def alternate_spellings(room_id):
    return {
        "braced": "{%s}" % room_id,
        "urn": f"urn:uuid:{room_id}",
        "unhyphenated": room_id.hex,
        "upper case": str(room_id).upper(),
    }


def malformed_bodies():
    """Every shape of bad body, and the code the surface answers it with."""
    good = name_blob_b64()
    return {
        "an array body": ([1, 2], "invalid_request"),
        "a string body": ("hello", "invalid_request"),
        "a number body": (5, "invalid_request"),
        "a bool body": (True, "invalid_request"),
        "a null body": (None, "invalid_request"),
        "a missing name": ({}, "invalid_request"),
        "a name sent as a number": ({"name_blob": 5}, "invalid_request"),
        "a name sent as a float": ({"name_blob": 1.5}, "invalid_request"),
        "a name sent as a bool": ({"name_blob": True}, "invalid_request"),
        "a name sent as null": ({"name_blob": None}, "invalid_request"),
        "a name sent as an array": ({"name_blob": [good]}, "invalid_request"),
        "a name sent as an object": ({"name_blob": {"b": good}}, "invalid_request"),
        "an empty name": ({"name_blob": ""}, "invalid_request"),
        "an oversized name string": (
            {"name_blob": "A" * (MAX_NAME_CHARS + 1)},
            "invalid_request",
        ),
        "an unknown field beside a good name": (
            {"name_blob": good, "owner": "alice"},
            "invalid_request",
        ),
        "an unknown field alone": ({"owner": "alice"}, "invalid_request"),
        "a name outside the base64 alphabet": ({"name_blob": "!!!!"}, "bad_bucket"),
        "a name with an embedded newline": ({"name_blob": "QUFB\nQUFB"}, "bad_bucket"),
        "a name with an embedded nul": ({"name_blob": "QUFB\x00QUFB"}, "bad_bucket"),
        "a name with an embedded bell": ({"name_blob": "QUFB\x07QUFB"}, "bad_bucket"),
        "a name at the character bound": (
            {"name_blob": "A" * MAX_NAME_CHARS},
            "bad_bucket",
        ),
        "a name one byte under the small bucket": (
            {"name_blob": base64.b64encode(b"u" * (min(NAME_BUCKETS) - 1)).decode()},
            "bad_bucket",
        ),
        "a name one byte over the small bucket": (
            {"name_blob": base64.b64encode(b"o" * (min(NAME_BUCKETS) + 1)).decode()},
            "bad_bucket",
        ),
        "a name one byte under the large bucket": (
            {"name_blob": base64.b64encode(b"u" * (max(NAME_BUCKETS) - 1)).decode()},
            "bad_bucket",
        ),
        "a name one byte over the large bucket": (
            {"name_blob": base64.b64encode(b"o" * (max(NAME_BUCKETS) + 1)).decode()},
            "bad_bucket",
        ),
        "a name between the two buckets": (
            {"name_blob": base64.b64encode(b"m" * 640).decode()},
            "bad_bucket",
        ),
    }


@pytest.fixture
def headers(active_user, device, bearer):
    return bearer(active_user, device)


def body_routes(room):
    """The two routes that read a body, as `(method, url)`."""
    return [("POST", ROOMS_URL), ("PUT", f"{ROOMS_URL}/{room.id}")]


def path_routes(segment):
    """The three routes that read a capability id out of the path."""
    return [
        ("GET", f"{ROOMS_URL}/{segment}", {}),
        ("PUT", f"{ROOMS_URL}/{segment}", {"json": {"name_blob": name_blob_b64()}}),
        ("POST", f"{ROOMS_URL}/{segment}/token", {}),
    ]


@pytest.mark.parametrize("case", list(malformed_bodies()))
def test_a_malformed_body_is_the_documented_400_on_both_writing_routes(
    http, headers, room, case
):
    body, expected = malformed_bodies()[case]

    for method, url in body_routes(room):
        response = http.request(method, url, json=body, headers=headers)

        assert response.status_code == 400, f"{case} on {method} {url}"
        assert envelope(response, expected)["code"] == expected


@pytest.mark.parametrize("case", list(malformed_bodies()))
def test_a_malformed_body_changes_no_row_and_echoes_nothing(http, headers, room, case):
    """The refusal must not become an oracle: `detail` may name the field that
    failed, never the ciphertext that failed it."""
    body, _expected = malformed_bodies()[case]
    sent = json.dumps(body)

    for method, url in body_routes(room):
        response = http.request(method, url, json=body, headers=headers)

        assert sent not in response.text
        blob = body.get("name_blob") if isinstance(body, dict) else None
        if isinstance(blob, str) and blob:
            assert blob not in response.text
    assert Room.objects.count() == 1
    room.refresh_from_db()
    assert bytes(room.name_blob) == b"n" * NAME_LEN


def test_a_body_that_is_not_json_at_all_is_an_invalid_request(http, headers, room):
    for method, url in body_routes(room):
        response = http.request(
            method,
            url,
            content=b"{not json",
            headers={**headers, "Content-Type": "application/json"},
        )

        assert response.status_code == 400
        envelope(response, "invalid_request")


def test_a_body_past_the_route_cap_is_a_payload_too_large_without_an_echo(
    http, headers, room
):
    """Counted as the bytes arrive rather than read from `Content-Length`, so the
    answer is the documented `413` and not a `500` from a half-read body."""
    oversized = "A" * (BODY_CAP_BYTES + 1024)

    for method, url in body_routes(room):
        response = http.request(
            method, url, json={"name_blob": oversized}, headers=headers
        )

        assert response.status_code == 413
        envelope(response, "payload_too_large")
        assert oversized not in response.text


@pytest.mark.parametrize("case", list(BAD_PATH_SEGMENTS))
def test_a_capability_id_the_parser_refuses_is_an_invalid_request_everywhere(
    http, headers, case
):
    segment = BAD_PATH_SEGMENTS[case]

    for method, url, kwargs in path_routes(segment):
        response = http.request(method, url, headers=headers, **kwargs)

        assert response.status_code == 400, f"{case} on {method} {url}"
        detail = envelope(response, "invalid_request")["detail"]
        assert set(detail) == {"room_id"}


@pytest.mark.parametrize("case", list(BAD_PATH_SEGMENTS))
def test_a_refused_capability_id_is_never_quoted_back_whole(http, headers, case):
    """Pydantic names the single character that failed the parse, which is why
    this asserts the whole segment rather than a substring: a refusal that echoed
    the id would hand an attacker a confirmed capability out of a log or a proxy
    cache."""
    segment = BAD_PATH_SEGMENTS[case]

    for method, url, kwargs in path_routes(segment):
        response = http.request(method, url, headers=headers, **kwargs)

        assert segment not in response.text
        assert unquote(segment) not in response.text


def test_every_uuid_spelling_of_one_capability_names_the_same_room(
    http, headers, room, voice_settings
):
    """The rare case: Python's UUID parser accepts four spellings of the same 128
    bits, so a client that stored a braced or unhyphenated id still reaches its
    room — and the answer always names the canonical form back."""
    for case, spelling in alternate_spellings(room.id).items():
        read = http.get(f"{ROOMS_URL}/{spelling}", headers=headers)
        minted = http.post(f"{ROOMS_URL}/{spelling}/token", headers=headers)

        assert read.status_code == 200, case
        assert read.json()["room_id"] == str(room.id), case
        assert minted.status_code == 200, case


def test_a_duplicated_name_key_settles_on_the_last_value_rather_than_failing(
    http, headers
):
    """JSON permits a key twice and the two decoders in front of this route could
    disagree about which wins. One does win, deterministically, and the stored row
    proves which — a `500` from a disagreement would be the defect."""
    body = '{"name_blob": "%s", "name_blob": "%s"}' % (
        name_blob_b64(b"1"),
        name_blob_b64(b"2"),
    )

    response = http.post(
        ROOMS_URL,
        content=body.encode(),
        headers={**headers, "Content-Type": "application/json"},
    )

    assert response.status_code == 201
    room = Room.objects.get(id=response.json()["room_id"])
    assert bytes(room.name_blob) == b"2" * NAME_LEN


def test_a_token_mint_ignores_a_body_it_never_declared(
    http, headers, room, voice_settings
):
    """The mint reads nothing but the path and the credential, so a body — even a
    hostile one — changes neither the answer nor the grant."""
    response = http.post(
        f"{ROOMS_URL}/{room.id}/token", json={"room": "someone-elses"}, headers=headers
    )

    assert response.status_code == 200
    assert set(response.json()) == {"url", "token", "expires_in"}


@settings(max_examples=25)
@given(
    segment=st.text(
        alphabet="0123456789abcdefABCDEF-{}:urn %\x00\x01\x7f.é", min_size=2, max_size=48
    )
)
def test_no_capability_id_a_client_can_spell_produces_anything_but_a_documented_answer(
    http, headers, segment
):
    """The property behind the table above, over the shapes a client can actually
    put in a path. Only the documented statuses, always the envelope, never the
    segment quoted back."""
    response = http.get(f"{ROOMS_URL}/{quote(segment, safe='')}", headers=headers)

    assert response.status_code in {400, 404}
    body = response.json()
    assert set(body) == {"code", "detail"}
    assert body["code"] in {"invalid_request", "not_found"}
    assert segment not in response.text


@settings(max_examples=25)
# The two lengths that must be accepted, pinned as examples so the accepting half
# of the property is exercised rather than left to the strategy to stumble on.
@example(size=min(NAME_BUCKETS))
@example(size=max(NAME_BUCKETS))
@given(size=st.integers(min_value=1, max_value=LARGEST_DECODABLE))
def test_a_name_is_created_exactly_on_a_bucket_length_and_refused_otherwise(
    http, headers, size
):
    """The bucket rule as a property over every byte count the character bound
    admits: exactly the declared lengths are stored, everything else is
    `bad_bucket`, and neither answer carries the blob."""
    blob = base64.b64encode(b"p" * size).decode()

    response = http.post(ROOMS_URL, json={"name_blob": blob}, headers=headers)

    if size in set(NAME_BUCKETS):
        assert response.status_code == 201
        assert set(response.json()) == {"room_id"}
    else:
        assert response.status_code == 400
        assert response.json() == {"code": "bad_bucket", "detail": "Invalid payload."}
    assert blob not in response.text
