"""The input contract of the devices surface: the two total functions it rests on,
and the refusal every route owes a malformed body.

`devices/schemas.py` says of itself that nothing here is verified — every bound is a
malformed-input guard that keeps a wrong-sized value out of a fixed-width column or
away from an unbounded decode. Two of those guards are total functions, and their
totality is the whole point:

* `page_bounds` sits on the one route a client polls with a bookmark it stored
  itself. A stale or corrupted bookmark must page from the start, never 400.
* `_b64` is the only door bytes enter through, and the order of its three checks is
  what keeps an arbitrarily long string away from `b64decode`.

The route table in the second half is the same contract from outside: every
body-carrying route answers `400` with the envelope for a body that is not an
object, a field of the wrong type, an oversized string, invalid base64, an
off-bucket length, a duplicate id, an unknown field, or a control character — and
never a `500`. The paging invariants of the function `page_bounds` feeds live in
`test_device_log.py`, beside the log they page over.
"""

import base64

import pytest
from hypothesis import given, settings
from hypothesis import strategies as st
from pydantic_core import PydanticCustomError

from devices.models import Device, OneTimePrekey
from devices.schemas import (
    DEVICELOG_PAGE_CAP,
    MAX_CLAIM_DEVICE_IDS,
    MAX_LABEL_CHARS,
    MAX_PUBKEY_CHARS,
    _b64,
    page_bounds,
)

from .conftest import (
    DEVICES_URL,
    cross_sig_b64,
    label_blob,
    pq_pubkey,
    pubkey,
    publish_identity,
    register_payload,
    stock_prekeys,
)

pytestmark = pytest.mark.django_db(transaction=True)

IDENTITY_URL = "/api/v1/me/identity"
LOG_URL = "/api/v1/me/devicelog"

# Anything a JSON body or a query string can put in front of these functions, plus
# the Python values a caller could pass directly. Bounded, because a property suite
# is a gate and not a fuzzing campaign.
ANY_INPUT = st.one_of(
    st.none(),
    st.booleans(),
    st.integers(),
    st.floats(allow_nan=True, allow_infinity=True),
    st.text(max_size=120),
    st.binary(max_size=120),
    st.lists(st.integers(), max_size=3),
    st.dictionaries(st.text(max_size=4), st.integers(), max_size=3),
)

# Text that decodes about as often as it fails to, so the decode branch is explored
# rather than assumed.
ANY_TEXT = st.one_of(
    st.text(max_size=120),
    st.binary(max_size=80).map(lambda raw: base64.b64encode(raw).decode()),
)

# Everything a query string can put in front of `page_bounds`, which is the whole of
# its domain: `peer_device_log` declares both parameters `str | None`, so a value of
# any other Python type never reaches it. The literals are the strings that make
# `int()` interesting — the ones it accepts through whitespace or a non-ASCII digit,
# and the float-shaped ones it refuses.
QUERY_VALUE = st.one_of(
    st.none(),
    st.text(max_size=40),
    st.integers().map(str),
    st.sampled_from(
        [
            "inf",
            "-inf",
            "nan",
            "1e999",
            "0x10",
            "  12  ",
            "12\n",
            "-0",
            "０１２",
            "9" * 40,
        ]
    ),
)

B64_ERRORS = {"b64_type", "b64_length", "b64_invalid"}


# --- page_bounds is total ------------------------------------------------------


@given(after=QUERY_VALUE, limit=QUERY_VALUE)
def test_page_bounds_answers_two_ints_for_any_query_value_property(after, limit):
    """The normal path and every error path at once: no value a query string can
    carry makes this raise, which is what keeps a stale bookmark from answering 400
    on the one route a client polls.

    The domain is `str | None` because that is what `peer_device_log` declares and
    therefore all `page_bounds` can be handed. It is not total over every Python
    value: `_int` catches `TypeError` and `ValueError`, so `float("inf")` escapes as
    `OverflowError`. No route can produce one.
    """
    cursor, size = page_bounds(after, limit)

    assert type(cursor) is int
    assert type(size) is int


@given(after=QUERY_VALUE, limit=QUERY_VALUE)
def test_page_bounds_clamps_every_limit_into_the_published_window_property(after, limit):
    """`devices/API.md` publishes "clamped into [1, 200]" for the page size. A limit
    of 0 would page forever and a limit of a million is an unbounded read."""
    _cursor, size = page_bounds(after, limit)

    assert 1 <= size <= DEVICELOG_PAGE_CAP


@given(after=QUERY_VALUE, limit=QUERY_VALUE)
def test_page_bounds_is_a_fixed_point_on_its_own_output_property(after, limit):
    """Clamped values pass through unchanged, so a caller that feeds a page's own
    bounds back — which is what walking a cursor does — cannot drift."""
    once = page_bounds(after, limit)

    assert page_bounds(str(once[0]), str(once[1])) == once


@given(
    smaller=st.integers(min_value=-1000, max_value=1000),
    larger=st.integers(min_value=-1000, max_value=1000),
)
def test_page_bounds_never_shrinks_a_larger_limit_property(smaller, larger):
    """Monotone, rather than a second copy of the clamp arithmetic: asking for more
    never yields a smaller page."""
    low, high = sorted((smaller, larger))

    assert page_bounds(None, low)[1] <= page_bounds(None, high)[1]


@pytest.mark.parametrize(
    "after, expected",
    [("42", 42), (7, 7), ("-3", -3), ("abc", -1), (None, -1), ("", -1), ("1.5", -1)],
)
def test_a_junk_cursor_falls_back_to_the_start_of_the_log(after, expected):
    """The boundary the property cannot state: which cursor a junk value becomes.
    -1 is the start, because the read is `seq > after` and `seq` counts from 0."""
    assert page_bounds(after, None)[0] == expected


# --- the base64 door is total, and its checks run in one order -----------------


@given(value=ANY_INPUT, cap=st.integers(min_value=0, max_value=200))
def test_the_base64_validator_returns_bytes_or_its_own_error_property(value, cap):
    """Total over arbitrary input: every path out of `_b64` is either bytes or one
    of the three errors this project raises. A `binascii.Error`, a `TypeError` or a
    `ValueError` escaping instead is a 500 on input the schema exists to filter."""
    try:
        decoded = _b64(value, cap)
    except PydanticCustomError as error:
        assert error.type in B64_ERRORS
    else:
        assert isinstance(decoded, bytes)


@given(value=ANY_TEXT.filter(bool))
def test_an_over_cap_string_is_refused_for_length_before_it_is_decoded_property(value):
    """The ordering `devices/schemas.py` documents at MAX_PUBKEY_CHARS: unbounded, a
    client could push an arbitrarily long string into `b64decode` before any length
    check runs. So a string past the cap answers `b64_length` whatever it contains —
    valid base64 included, which is the case that would otherwise decode first."""
    with pytest.raises(PydanticCustomError) as raised:
        _b64(value, len(value) - 1)

    assert raised.value.type == "b64_length"


@given(value=ANY_TEXT)
def test_a_string_within_the_cap_is_judged_only_on_whether_it_decodes_property(value):
    """The other side of the same ordering: at or under the cap the length check has
    nothing to say, so the answer is the decode's."""
    try:
        decoded = _b64(value, len(value))
    except PydanticCustomError as error:
        assert error.type == "b64_invalid"
    else:
        assert decoded == base64.b64decode(value, validate=True)


@given(
    value=ANY_INPUT.filter(lambda candidate: not isinstance(candidate, str)),
    cap=st.integers(min_value=0, max_value=10),
)
def test_a_non_string_is_refused_for_its_type_before_its_length_property(value, cap):
    """The first check of the three. `len()` of an int raises `TypeError`, so a type
    check that ran second would be a 500 rather than a named field error."""
    with pytest.raises(PydanticCustomError) as raised:
        _b64(value, cap)

    assert raised.value.type == "b64_type"


# --- the same contract from outside: every route, every malformed shape --------


def bodied_routes(device_id, user_id):
    """Every route of `devices/routes.py` that reads a body, with one that works."""
    return {
        "register a device": ("post", DEVICES_URL, register_payload()),
        "relabel a device": (
            "put",
            f"{DEVICES_URL}/{device_id}",
            {"label_blob": label_blob()},
        ),
        "replenish prekeys": (
            "put",
            f"{DEVICES_URL}/{device_id}/prekeys",
            {"otpks": [{"key_id": 1, "pub": pubkey()}]},
        ),
        "publish an identity": (
            "put",
            IDENTITY_URL,
            {
                "master_pub": pubkey(b"m"),
                "self_signing_pub": pubkey(b"s"),
                "user_signing_pub": pubkey(b"u"),
                "master_sig": cross_sig_b64(),
                "version": 1,
            },
        ),
        "append to the device log": (
            "post",
            LOG_URL,
            {"records": [{"blob": label_blob()}]},
        ),
        "claim prekey bundles": (
            "post",
            f"/api/v1/users/{user_id}/keys/claim",
            {"device_ids": []},
        ),
    }


def send(http, http_method, url, body, headers):
    return getattr(http, http_method)(url, json=body, headers=headers)


def assert_envelope(response, code):
    """400 with the envelope `core/API.md` fixes, and never a 500."""
    assert response.status_code == 400, response.text
    body = response.json()
    assert body["code"] == code
    assert body["detail"]


@pytest.mark.parametrize("name", list(bodied_routes("d", "u")))
@pytest.mark.parametrize("body", [["nope"], "nope", 5], ids=repr)
def test_a_body_that_is_not_an_object_is_a_400_on_every_route(
    http, active_user, device, bearer, peer, name, body
):
    method, url, _valid = bodied_routes(device.id, peer.id)[name]

    response = send(http, method, url, body, bearer(active_user, device))

    assert_envelope(response, "invalid_request")
    assert response.json()["detail"]["body"]  # it belongs to no field


@pytest.mark.parametrize("name", list(bodied_routes("d", "u")))
def test_an_unknown_field_is_refused_on_every_route(
    http, active_user, device, bearer, peer, name
):
    """`extra="forbid"`, so an injected key is a refusal rather than a value that is
    silently dropped."""
    method, url, valid = bodied_routes(device.id, peer.id)[name]

    response = send(
        http, method, url, {**valid, "private_key": "oops"}, bearer(active_user, device)
    )

    assert_envelope(response, "invalid_request")
    assert "private_key" in response.json()["detail"]


@pytest.mark.parametrize(
    "name, field, value",
    [
        ("register a device", "spk_id", "1"),
        ("register a device", "otpks", {}),
        ("relabel a device", "label_blob", 5),
        ("replenish prekeys", "otpks", "one"),
        ("publish an identity", "version", "1"),
        ("append to the device log", "records", {}),
        ("claim prekey bundles", "device_ids", "abc"),
    ],
)
def test_a_field_of_the_wrong_json_type_is_refused_not_converted(
    http, active_user, device, bearer, peer, name, field, value
):
    """Strict mode: `"1"` is not an integer here, so no value changes shape on the
    way into a column."""
    method, url, valid = bodied_routes(device.id, peer.id)[name]

    response = send(
        http, method, url, {**valid, field: value}, bearer(active_user, device)
    )

    assert_envelope(response, "invalid_request")
    assert field in response.json()["detail"]


@pytest.mark.parametrize(
    "name, field, value",
    [
        ("register a device", "ik_pub", "A" * (MAX_PUBKEY_CHARS + 1)),
        ("register a device", "label_blob", "A" * (MAX_LABEL_CHARS + 1)),
        ("publish an identity", "master_pub", "A" * (MAX_PUBKEY_CHARS + 1)),
    ],
)
def test_an_oversized_string_is_refused_by_length(
    http, active_user, device, bearer, peer, name, field, value
):
    """The bound is on the encoded string, so the oversized value never reaches a
    decode. `detail` names the field and never echoes what was sent."""
    method, url, valid = bodied_routes(device.id, peer.id)[name]

    response = send(
        http, method, url, {**valid, field: value}, bearer(active_user, device)
    )

    assert_envelope(response, "invalid_request")
    assert field in response.json()["detail"]
    assert value not in response.text


@pytest.mark.parametrize("junk", ["not-base64!!", "AAA\x00AAAA", "A" * 33, "====", "\n"])
def test_invalid_base64_and_control_characters_are_refused_field_by_field(
    http, active_user, device, bearer, junk
):
    response = http.post(
        DEVICES_URL,
        json=register_payload(ik_pub=junk),
        headers=bearer(active_user, device),
    )

    assert_envelope(response, "invalid_request")
    assert "ik_pub" in response.json()["detail"]


@pytest.mark.parametrize("nbytes", [1, 255, 257, 1025])
@pytest.mark.parametrize("route", ["register a device", "append to the device log"])
def test_an_off_bucket_blob_is_bad_bucket_without_an_echo(
    http, active_user, device, bearer, peer, nbytes, route
):
    """`bad_bucket` rather than `invalid_request`: the blob decodes in a model-level
    validator, so it runs only once every field has validated, and it echoes
    nothing."""
    off_bucket = base64.b64encode(b"x" * nbytes).decode()
    method, url, valid = bodied_routes(device.id, peer.id)[route]
    body = (
        {**valid, "label_blob": off_bucket}
        if route == "register a device"
        else {"records": [{"blob": off_bucket}]}
    )

    response = send(http, method, url, body, bearer(active_user, device))

    assert_envelope(response, "bad_bucket")
    assert off_bucket not in response.text


@pytest.mark.parametrize(
    "route, field, item",
    [
        ("register a device", "otpks", {"key_id": 3, "pub": pubkey()}),
        ("replenish prekeys", "otpks", {"key_id": 3, "pub": pubkey()}),
        ("register a device", "pq_otpks", {"key_id": 3, "pub": pq_pubkey()}),
        ("replenish prekeys", "pq_otpks", {"key_id": 3, "pub": pq_pubkey()}),
    ],
)
def test_a_duplicate_key_id_inside_one_payload_is_refused(
    http, active_user, device, bearer, peer, route, field, item
):
    """`unique (device, key_id)` would make a repeated id an IntegrityError out of
    `bulk_create`, i.e. a 500 on malformed client input."""
    method, url, valid = bodied_routes(device.id, peer.id)[route]

    response = send(
        http, method, url, {**valid, field: [item, item]}, bearer(active_user, device)
    )

    assert_envelope(response, "invalid_request")


def test_a_repeated_device_id_in_a_claim_yields_one_bundle_and_burns_one_key(
    http, active_user, device, bearer, peer, peer_device
):
    """The one "duplicate id" the schema deliberately does not refuse: `device_ids`
    is a filter, not a list of work items, so repeating one is the same request. It
    must not fan out into two bundles or burn two one-time prekeys."""
    stock_prekeys(peer_device, 2)

    response = http.post(
        f"/api/v1/users/{peer.id}/keys/claim",
        json={"device_ids": [str(peer_device.id)] * 3},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200
    assert len(response.json()["bundles"]) == 1
    assert OneTimePrekey.objects.filter(device=peer_device).count() == 1


def test_an_oversized_claim_list_is_refused_before_the_planner_sees_it(
    http, active_user, device, bearer, peer, peer_device
):
    """The boundary either side of MAX_CLAIM_DEVICE_IDS: the cap itself is accepted,
    one past it is not."""
    headers = bearer(active_user, device)
    at_cap = [str(peer_device.id)] * MAX_CLAIM_DEVICE_IDS
    url = f"/api/v1/users/{peer.id}/keys/claim"

    assert http.post(url, json={"device_ids": at_cap}, headers=headers).status_code == 200

    response = http.post(
        url, json={"device_ids": at_cap + [str(peer_device.id)]}, headers=headers
    )

    assert_envelope(response, "invalid_request")


@pytest.mark.parametrize(
    "name, method, url, body",
    [
        ("relabel", "put", f"{DEVICES_URL}/not-a-uuid", {"label_blob": label_blob()}),
        ("revoke", "delete", f"{DEVICES_URL}/not-a-uuid", None),
        ("replenish", "put", f"{DEVICES_URL}/not-a-uuid/prekeys", {"otpks": []}),
        ("prekey count", "get", f"{DEVICES_URL}/not-a-uuid/prekeys/count", None),
        ("peer devices", "get", "/api/v1/users/not-a-uuid/devices", None),
        ("peer identity", "get", "/api/v1/users/not-a-uuid/identity", None),
        ("peer device log", "get", "/api/v1/users/not-a-uuid/devicelog", None),
        ("claim", "post", "/api/v1/users/not-a-uuid/keys/claim", {}),
    ],
)
def test_a_path_id_that_is_not_a_uuid_is_a_400_and_never_a_404(
    http, active_user, device, bearer, name, method, url, body
):
    """A 404 here would say "no such device" about a request that never named one,
    and an unparsed value reaching a uuid column is a 500."""
    headers = bearer(active_user, device)

    response = (
        getattr(http, method)(url, json=body, headers=headers)
        if body is not None
        else getattr(http, method)(url, headers=headers)
    )

    assert_envelope(response, "invalid_request")
    named = response.json()["detail"]
    assert "device_id" in named or "user_id" in named


def test_a_junk_if_none_match_serves_the_list_rather_than_failing(
    http, active_user, device, bearer
):
    """The header is a bookmark the client stored, so a corrupted one must fall back
    to a full answer — the same stance `page_bounds` takes on a junk cursor."""
    response = http.get(
        DEVICES_URL, headers={**bearer(active_user, device), "If-None-Match": "garbage"}
    )

    assert response.status_code == 200
    assert response.headers["etag"] != "garbage"


def test_a_registration_with_an_empty_prekey_list_is_accepted(
    http, active_user, device, bearer
):
    """`otpks` is required but may be empty: a device that arrives with no one-time
    keys is served as an exhausted pool until it replenishes, which is the state
    every device reaches on its own anyway."""
    publish_identity(active_user)

    response = http.post(
        DEVICES_URL, json=register_payload(otpks=0), headers=bearer(active_user, device)
    )

    assert response.status_code == 201
    born = response.json()["device_id"]
    assert OneTimePrekey.objects.filter(device_id=born).count() == 0


@settings(max_examples=25)
@given(
    label=st.text(
        alphabet=st.characters(blacklist_categories=("Cs",)), min_size=1, max_size=60
    )
)
def test_no_arbitrary_label_string_ever_reaches_the_column_property(
    http, active_user, device, bearer, label
):
    """A stored label is base64 of an exact bucket length, so no string this short
    can be one. Whatever it contains — control characters, a lone surrogate pair
    escape, padding — the answer is a refusal with the envelope, never a 500 and
    never a stored row."""
    response = http.put(
        f"{DEVICES_URL}/{device.id}",
        json={"label_blob": label},
        headers=bearer(active_user, device),
    )

    assert response.status_code == 400
    assert response.json()["code"] in {"invalid_request", "bad_bucket"}
    assert Device.objects.get(pk=device.id).label_blob is None
