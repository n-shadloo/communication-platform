"""The committed OpenAPI document, as something a response can be held to.

`backend/openapi.json` is what a client generates from, so a body this server sends
that the document does not describe is a client that breaks on a field it was never
told about. The drift gate (`manage.py openapi --check`) proves the document matches
the routes; nothing proved the *responses* match the document, because a schema is a
description of a shape and FastAPI serialises through the response model rather than
against the document it later emits.

This module closes that gap. `check` is called by the test client in
`backend/conftest.py` for every response the suite produces, so the whole suite —
not one file of contract tests — is the sample. `jsonschema` is the reference
implementation of the 2020-12 dialect the document declares, so a body is judged
under the rules a client's own generator reads it by.

Nothing here is imported by a production module.
"""

import json
from functools import lru_cache

from django.conf import settings
from jsonschema import Draft202012Validator
from starlette.routing import compile_path

ARTEFACT = "openapi.json"
JSON_MEDIA_TYPE = "application/json"

DOCUMENT = json.loads((settings.BASE_DIR / ARTEFACT).read_text(encoding="utf-8"))

# (method, compiled path regex, path template) for every operation the document
# declares. Compiled from the templates rather than read off the router, because the
# document is the thing under test and reading the router would make the two agree by
# construction.
MATCHERS = tuple(
    (method.upper(), compile_path(path)[0], path)
    for path, operations in DOCUMENT["paths"].items()
    for method in operations
)

# Every (method, template, status) the document declares an answer for. The table
# `core/tests/test_contract.py` walks.
DECLARED = frozenset(
    (method.upper(), path, status)
    for path, operations in DOCUMENT["paths"].items()
    for method, operation in operations.items()
    for status in operation["responses"]
)


def template_of(method, path):
    """The document's template for a concrete request path, or None when the path
    is one the Django application answers."""
    for candidate, regex, template in MATCHERS:
        if candidate == method.upper() and regex.match(path):
            return template
    return None


@lru_cache(maxsize=None)
def _validator(method, template, status):
    """The validator for one answer, or None when the document declares no JSON body
    for it — a `204`, the attachment download, or a status with no content block.

    `components` rides along as a sibling of the response schema so that the
    document's own `#/components/schemas/…` references resolve inside it. A sibling
    of `$ref` is not a keyword in this dialect, so it changes nothing about what the
    schema asserts.
    """
    operation = DOCUMENT["paths"][template][method.lower()]
    response = operation["responses"].get(str(status))
    if response is None:
        return None
    schema = response.get("content", {}).get(JSON_MEDIA_TYPE, {}).get("schema")
    if schema is None:
        return None
    return Draft202012Validator(
        {**schema, "components": DOCUMENT["components"]},
        # `format` is an annotation in this dialect unless a checker is handed in.
        # With one, `uuid` and `date` become assertions — which is what the client
        # reads them as — and every format jsonschema has no checker for stays an
        # annotation rather than becoming a false failure.
        format_checker=Draft202012Validator.FORMAT_CHECKER,
    )


# The refusals this surface answers before it has chosen a route. `api/schema.py`
# records why they belong to no operation and therefore appear on none of them: an
# unknown `Host`, a path no route serves, a method a route does not carry, and a body
# above the cap of its route class. Matched as whole bodies rather than as bare
# statuses, so a route that answered one of these numbers for a reason of its own is
# still held to the document.
BEFORE_THE_ROUTE = (
    {"code": "invalid_request", "detail": {"host": ["Unknown host."]}},
    {"code": "not_found", "detail": "No such route or resource."},
    {"code": "method_not_allowed", "detail": "That method is not allowed."},
    {"code": "payload_too_large", "detail": "Request body is too large."},
)


def declares(method, template, status):
    return (method.upper(), template, str(status)) in DECLARED


def check(method, path, status, content_type, body):
    """Raise when a response contradicts the document. Silent otherwise.

    Returns the template the response was matched to, or None when it belongs to no
    documented operation — the admin, the static files, and the documentation routes
    of the development application all reach here and none of them is in the
    contract.
    """
    template = template_of(method, path)
    if template is None:
        return None
    decoded = (
        json.loads(body) if body and content_type.startswith(JSON_MEDIA_TYPE) else None
    )
    if decoded in BEFORE_THE_ROUTE:
        return template
    if not declares(method, template, status):
        raise AssertionError(
            f"{method} {template} answered {status}, which "
            f"{ARTEFACT} does not declare for it"
        )
    if not body or not content_type.startswith(JSON_MEDIA_TYPE):
        # A `204`, the attachment download, and the empty body of the rename all
        # reach here with nothing to validate.
        return template
    validator = _validator(method, template, status)
    if validator is None:
        return template
    errors = sorted(validator.iter_errors(decoded), key=lambda e: e.json_path)
    if errors:
        # The failing path and the rule, never the value: a response body of this
        # API is ciphertext or a token, and an assertion message is a log line by
        # another name.
        detail = "; ".join(f"{error.json_path} {error.validator}" for error in errors)
        raise AssertionError(
            f"{method} {template} {status} does not validate against {ARTEFACT}: {detail}"
        )
    return template
