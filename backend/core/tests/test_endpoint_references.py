"""The per-app `API.md` files, held to the code and to the generated document.

These files are the human half of the contract: the retry semantics, the bucket
rules and the close codes are things a schema cannot carry, so a client author
reads them and nothing compares them to the routes. This file is that comparison.

The shape it reads is the shape the files already use.

- A route section is an `##` heading whose body carries a `**Method:**` line and
  a `**Path:**` line, each naming its values in backticks.
- A response is a `###` heading inside that section whose text names a status in
  backticks. A trailing parenthesised verb — `(PUT)` — restricts it to that
  method; without one it belongs to every method of the section.
- The throttle scope is a line beginning ``Scope `name` ``.
- The retry semantics of a mutating route is a `**Retry semantics.**` paragraph.

Four statuses are not required per route, because a route inherits them from the
requirement it declares, from the request deadline and from the unhandled-failure
handler rather than from anything of its own: `core/API.md` carries their bodies
once for the whole surface. A route may still name one — `403 forbidden` and
`503 voice_unconfigured` are route-specific — but may never name a status the
code cannot answer.
"""

import json
import re

import pytest
from django.conf import settings

from core import buckets
from core.management.commands.openapi import ARTEFACT
from core.tests.test_route_table import LIMITER_PREFIX, served

REFERENCES = sorted(settings.BASE_DIR.glob("*/API.md"))

SECTION = re.compile(r"^##\s+(?!#)(.*)$", re.M)
METHOD_LINE = re.compile(r"^\*\*Method:\*\*\s*(.+)$", re.M)
PATH_LINE = re.compile(r"^\*\*Path:\*\*\s*(.+)$", re.M)
RESPONSE = re.compile(r"^###\s+.*?`(\d{3})[^`]*`(.*)$", re.M)
SCOPE = re.compile(r"^Scope `([a-z]+)`", re.M)
RETRY = re.compile(r"^\*\*Retry semantics\.\*\*", re.M)
BACKTICKED = re.compile(r"`([^`]+)`")
VERB = re.compile(r"\b(GET|POST|PUT|DELETE)\b")
MUTATING = {"POST", "PUT", "DELETE"}

# The refusals a route answers because of what it declares rather than what it
# does. `core/API.md` carries each body once.
INHERITED = {"401", "403", "500", "503"}

BUCKET_SETS = {
    "ENVELOPE_BUCKETS": buckets.ENVELOPE_BUCKETS,
    "PROFILE_BUCKETS": buckets.PROFILE_BUCKETS,
    "LABEL_BUCKETS": buckets.LABEL_BUCKETS,
    "NAME_BUCKETS": buckets.NAME_BUCKETS,
    "DEVICELOG_BUCKETS": buckets.DEVICELOG_BUCKETS,
    "BACKUP_BUCKETS": buckets.BACKUP_BUCKETS,
    "ATTACHMENT_BUCKETS": buckets.ATTACHMENT_BUCKETS,
}


def document():
    return json.loads((settings.BASE_DIR / ARTEFACT).read_text(encoding="utf-8"))


def documented_statuses():
    """(method, path) -> the statuses its `API.md` section publishes."""
    table = {}
    for method, path, body in sections():
        published = set()
        for status, tail in RESPONSE.findall(body):
            named = VERB.findall(tail.upper())
            if not named or method in named:
                published.add(status)
        table[(method, path)] = published
    return table


def sections():
    """(method, path, the body of the section that documents it)."""
    found = []
    for reference in REFERENCES:
        parts = SECTION.split(reference.read_text(encoding="utf-8"))
        # A preamble, then a heading and a body for each section after it.
        for body in parts[2::2]:
            methods, paths = METHOD_LINE.search(body), PATH_LINE.search(body)
            if not (methods and paths):
                continue
            for method in BACKTICKED.findall(methods.group(1)):
                for path in BACKTICKED.findall(paths.group(1)):
                    found.append((method.upper(), path, body))
    return found


def route_scopes():
    """(method, path) -> the throttle scope the code counts it against."""
    return {
        route: {
            name.removeprefix(LIMITER_PREFIX)
            for name in names
            if name.startswith(LIMITER_PREFIX)
        }
        for route, names in served().items()
    }


ROUTES = sorted(document()["paths"])
OPERATIONS = {
    (method.upper(), path): operation
    for path, methods in document()["paths"].items()
    for method, operation in methods.items()
}


def test_every_route_of_the_document_has_a_section():
    assert set(OPERATIONS) - set(documented_statuses()) == set()


def test_no_section_documents_a_route_the_surface_does_not_serve():
    assert set(documented_statuses()) - set(OPERATIONS) == set()


@pytest.mark.parametrize("route", sorted(OPERATIONS))
def test_every_route_publishes_the_statuses_it_can_answer(route):
    """Everything but the four a route inherits. A status the reference omits is
    one a client meets for the first time in production."""
    published = documented_statuses()[route]
    answerable = set(OPERATIONS[route]["responses"])

    assert answerable - INHERITED - published == set(), route


@pytest.mark.parametrize("route", sorted(OPERATIONS))
def test_no_route_publishes_a_status_the_code_cannot_answer(route):
    published = documented_statuses()[route]
    answerable = set(OPERATIONS[route]["responses"])

    assert published - answerable == set(), route


@pytest.mark.parametrize("route", sorted(OPERATIONS))
def test_every_route_names_the_throttle_scope_it_counts_against(route):
    """The scope, not just the rate: two routes on one scope share a counter, and
    a client that pages one is throttled on the other."""
    body = next(body for method, path, body in sections() if (method, path) == route)

    assert set(SCOPE.findall(body)) == route_scopes()[route], route


@pytest.mark.parametrize("route", sorted(key for key in OPERATIONS if key[0] in MUTATING))
def test_every_mutating_route_documents_what_a_retry_does(route):
    """ADR-0007 refuses an idempotency store, because a stored response for a send
    would link a sender to its recipients at rest. The retry semantics are what
    stands in its place, and they are contract rather than commentary."""
    body = next(body for method, path, body in sections() if (method, path) == route)

    assert RETRY.search(body) is not None, route


@pytest.mark.parametrize("name", sorted(BUCKET_SETS))
def test_core_publishes_every_bucket_set_that_exists(name):
    """An off-bucket payload is a `400 bad_bucket` with no echo, so the sizes are
    the only way a client learns what to pad to."""
    table = (settings.BASE_DIR / "core" / "API.md").read_text(encoding="utf-8")
    row = next(
        (line for line in table.splitlines() if line.startswith(f"| `{name}`")), None
    )
    assert row is not None, name

    published = [int(value.replace(",", "")) for value in re.findall(r"\d[\d,]*", row)]

    assert published == BUCKET_SETS[name], name
