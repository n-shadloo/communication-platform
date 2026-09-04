"""The one route `core/routes.py` serves, and the refusals around it.

The probe itself is three lines, so most of what a client can meet on this path is
what the surface answers *instead* of it: a mistyped path, a body it never reads,
a body too large to read. Every one of those is this API's error envelope and
never a `500` — a probe that answered a stack trace to an unauthenticated caller
would be the one route on the surface that did.
"""

import pytest
from django.conf import settings

from core.schemas import HealthOut

ENVELOPE_KEYS = {"code", "detail"}


def test_health_is_anonymous_and_reports_ok(http):
    """Serves the client's startup reachability probe."""
    response = http.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_discloses_no_version_or_build(http):
    assert set(http.get("/api/v1/health").json()) == {"status"}


@pytest.mark.django_db
def test_health_reads_no_state(http, django_assert_num_queries):
    """A liveness probe that queried the database would report the database, not
    the process, and would give an unauthenticated caller a way to load it."""
    with django_assert_num_queries(0):
        assert http.get("/api/v1/health").status_code == 200


def test_the_response_model_publishes_liveness_and_nothing_else():
    """No version, no build, no component status: each of those is a fact about
    the deployment that an unauthenticated caller would be handed."""
    assert set(HealthOut.model_fields) == {"status"}
    assert HealthOut.model_fields["status"].is_required()


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/health/",
        "/api/v1/health/extra",
        "/api/v1/heal",
        "/api/v1/HEALTH",
        "/api/v1/health%00",
        "/api/v1/health%0d%0aX-Injected:%20yes",
        "/api/v1/health" + "/x" * 200,
    ],
)
def test_a_path_that_is_not_the_probe_is_the_not_found_envelope(http, path):
    """Including the trailing slash, which is a `404` and never a redirect: the
    redirect would rebuild an absolute address from the scope path and drop any
    prefix a proxy stripped."""
    response = http.get(path)

    assert response.status_code == 404
    assert response.json() == {
        "code": "not_found",
        "detail": "No such route or resource.",
    }
    assert response.headers["content-type"].startswith("application/json")


@pytest.mark.parametrize(
    "query",
    [
        "?verbose=1",
        "?status=critical",
        "?" + "a" * 2000,
        "?blob=%00%01%02",
        "?repeated=1&repeated=2",
    ],
)
def test_an_unknown_query_string_is_ignored_rather_than_parsed(http, query):
    """The route declares no parameter, so nothing on this path validates a query
    — and a caller must not be able to turn one into a `500`."""
    response = http.get(f"/api/v1/health{query}")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.parametrize(
    "body",
    [b"", b"null", b"[]", b'{"status": "not ok"}', b"\x00\x01\x02", b"not json at all"],
)
def test_a_body_the_probe_never_reads_changes_nothing(http, body):
    """A `GET` may carry one, and a caller that sends a malformed one must get the
    probe's answer rather than a validation failure the route never asked for."""
    response = http.request("GET", "/api/v1/health", content=body)

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_a_body_the_probe_never_reads_is_never_counted_against_the_cap(http):
    """The probe carries the smallest limit class and still answers `200` to a
    body above it, which is the mechanism rather than a hole in it: `BodyCap`
    counts bytes inside the `receive` it hands the application, and a route that
    declares no body never calls it. `core/tests/test_request_limits.py::TestBodyCap`
    drives the same middleware under an application that does read, where the cap
    is what produces the `413`.

    What bounds this path is therefore one layer out — `client_max_body_size` in
    `ops/nginx` — plus uvicorn's own flow control, which stops reading from the
    socket while nothing is consuming. Asserted here so the behaviour is recorded
    rather than discovered by whoever next reads the cap table and assumes it
    covers every route.
    """
    oversized = b"x" * (settings.BODY_CAP_JSON_BYTES + 1)

    response = http.request("GET", "/api/v1/health", content=oversized)

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
    edge = "\n".join(
        conf.read_text() for conf in (settings.BASE_DIR / "ops" / "nginx").glob("*.conf")
    )
    assert "client_max_body_size" in edge


def test_no_refusal_on_this_path_is_ever_a_server_error(http):
    """The one assertion that holds over the whole file: every malformed shape
    above answers a described refusal, and the vocabulary has no room for an
    unhandled failure on a route that reads nothing."""
    shapes = [
        ("GET", "/api/v1/health/", {}),
        ("POST", "/api/v1/health", {"content": b"{}"}),
        ("PUT", "/api/v1/health", {"content": b"{}"}),
        ("GET", "/api/v1/health%00", {}),
        ("GET", "/api/v1/health", {"content": b"x" * (settings.BODY_CAP_JSON_BYTES + 1)}),
    ]

    for method, path, kwargs in shapes:
        response = http.request(method, path, **kwargs)

        assert response.status_code != 500, (method, path)
        assert set(response.json()) in ({"status"}, ENVELOPE_KEYS), (method, path)
