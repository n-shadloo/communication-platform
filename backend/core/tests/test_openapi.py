"""The OpenAPI document: what it must contain, and the drift gate that keeps it.

FastAPI has no counterpart to a generator warning. A route that declares no
response model reaches the document as an empty schema and raises nothing, so
both the drift gate and a diff against a released baseline would pass over a
document full of holes. This file is the completeness check instead: it walks the
generated document and fails a route whose declared set is missing what the route
itself implies. `api/schema.py` is the mechanism it holds to.
"""

import json
import warnings
from io import StringIO

import pytest
from django.conf import settings
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import override_settings
from fastapi.routing import iter_route_contexts

from api.auth import require_full_device, require_register_or_full
from api.schema import (
    FULL_DEVICE,
    INJECTED_VALIDATION_COMPONENTS,
    INJECTED_VALIDATION_STATUS,
    REGISTER_OR_FULL,
    UNIVERSAL,
    VOCABULARY,
)
from config.asgi import api_application, django_asgi_app
from core.management.commands.openapi import ARTEFACT, rendered
from core.tests.test_route_table import DOCUMENTATION
from devices.routes import require_own_device

ENVELOPE = "#/components/schemas/ErrorOut"
LIMITER_PREFIX = "rate_limit_"
# The statuses that are neither a success nor an error: a body was not sent
# because the client already holds it.
NOT_MODIFIED = "304"


DOCUMENT = api_application.openapi()

# Operation id -> the operation object. Built at collection: the document is a
# pure function of the routes and the models, so a tree that cannot produce one
# fails here rather than inside a test.
OPERATIONS = {
    operation["operationId"]: operation
    for path in DOCUMENT["paths"].values()
    for operation in path.values()
}

# Operation id -> the route it came from, keyed on the name because
# `api/schema.py` makes the handler name the operation identifier — which
# `test_the_operation_identifier_is_the_handler_name` is what proves.
ROUTES = {
    context.name: context
    for context in iter_route_contexts(api_application.routes)
    if context.methods is not None and context.path not in DOCUMENTATION
}

WITH_BODY = sorted(
    operation_id
    for operation_id, operation in OPERATIONS.items()
    if "requestBody" in operation
)

WITH_TYPED_PATH_PARAMETER = sorted(
    operation_id
    for operation_id, operation in OPERATIONS.items()
    if any(
        parameter["in"] == "path" and parameter["schema"].get("format")
        for parameter in operation.get("parameters", [])
    )
)


def statuses(operation, floor=0):
    return {status for status in operation["responses"] if int(status) >= floor}


def implied(context):
    """The statuses a route answers because of the dependencies it declares,
    whatever its own body and its own service do."""
    names = [dep.call.__name__ for dep in context.dependant.dependencies]
    codes = set(UNIVERSAL)
    if require_full_device.__name__ in names:
        codes |= set(FULL_DEVICE)
    if require_register_or_full.__name__ in names:
        codes |= set(REGISTER_OR_FULL)
    if require_own_device.__name__ in names:
        codes.add("forbidden")
    if any(name.startswith(LIMITER_PREFIX) for name in names):
        codes.add("throttled")
    return {str(VOCABULARY[code]) for code in codes}


def test_the_committed_artefact_is_the_generated_document():
    """The gate `manage.py openapi --check` runs in CI, run here too so a contract
    change that forgets the artefact fails in the suite rather than on the branch."""
    path = settings.BASE_DIR / ARTEFACT

    assert path.read_text(encoding="utf-8") == rendered(), (
        f"{ARTEFACT} has drifted. Run `python manage.py openapi`."
    )


def test_the_artefact_is_written_with_a_stable_key_order():
    """Two generations of one tree must produce one file, or every drift check
    after the first is noise."""
    assert (
        rendered() == json.dumps(json.loads(rendered()), indent=2, sort_keys=True) + "\n"
    )


@pytest.mark.parametrize("operation_id", sorted(OPERATIONS))
def test_every_operation_declares_exactly_one_success_response(operation_id):
    success = {
        status for status in OPERATIONS[operation_id]["responses"] if status[0] == "2"
    }

    assert len(success) == 1, operation_id


@pytest.mark.parametrize("operation_id", sorted(OPERATIONS))
def test_no_response_carries_an_untyped_body(operation_id):
    """The hole a missing response model leaves. FastAPI publishes `{}` for it,
    which is a well-formed document that describes nothing."""
    declared = OPERATIONS[operation_id]
    untyped = [
        f"{status} {media}"
        for status, response in declared["responses"].items()
        for media, body in response.get("content", {}).items()
        if not body.get("schema")
    ]

    assert untyped == [], operation_id


@pytest.mark.parametrize("operation_id", sorted(OPERATIONS))
def test_every_response_carries_a_description(operation_id):
    """The OpenAPI Response Object requires one, and a document that omits it
    fails validation in the client generator rather than here."""
    declared = OPERATIONS[operation_id]
    undescribed = [
        status
        for status, response in declared["responses"].items()
        if not response.get("description")
    ]

    assert undescribed == [], operation_id


@pytest.mark.parametrize("operation_id", sorted(OPERATIONS))
def test_every_error_response_renders_the_envelope(operation_id):
    """One envelope on every error of this API, so a client branches on `code`
    rather than on a shape it has to discover per route."""
    declared = OPERATIONS[operation_id]
    wrong = {
        status: response.get("content")
        for status, response in declared["responses"].items()
        if int(status) >= 400
        and response["content"]["application/json"]["schema"].get("$ref") != ENVELOPE
    }

    assert wrong == {}, operation_id


@pytest.mark.parametrize("operation_id", sorted(ROUTES))
def test_every_operation_declares_the_errors_its_dependencies_imply(operation_id):
    """The gate on the next endpoint. A route that declares a requirement and a
    limiter can answer their refusals whatever its own body does, so the document
    carries them or this fails."""
    missing = implied(ROUTES[operation_id]) - statuses(OPERATIONS[operation_id])

    assert missing == set(), operation_id


@pytest.mark.parametrize("operation_id", WITH_BODY)
def test_an_operation_that_takes_a_body_declares_the_two_refusals_of_one(
    operation_id,
):
    """A validation failure and a body above the route cap. Both are answered
    before the handler runs, so neither is visible in the handler's own code."""
    missing = {"400", "413"} - statuses(OPERATIONS[operation_id])

    assert missing == set(), operation_id


@pytest.mark.parametrize("operation_id", WITH_TYPED_PATH_PARAMETER)
def test_an_operation_with_a_typed_path_parameter_declares_the_validation_refusal(
    operation_id,
):
    """A path segment that must parse — every `{user_id}`, `{device_id}` and
    `{room_id}` is a UUID — is a `400 invalid_request` on a value that does not."""
    assert "400" in statuses(OPERATIONS[operation_id]), operation_id


@pytest.mark.parametrize("operation_id", sorted(OPERATIONS))
def test_no_operation_publishes_a_status_outside_the_vocabulary(operation_id):
    """Every error status of this surface belongs to a code `core/API.md`
    publishes. `304` is the one non-error status a route answers besides its own
    success."""
    declared = OPERATIONS[operation_id]
    known = {str(status) for status in VOCABULARY.values()} | {NOT_MODIFIED}
    unknown = {status for status in statuses(declared, floor=300) if status not in known}

    assert unknown == set(), operation_id


def test_the_operation_identifier_is_the_handler_name():
    """The identifier is the method name a generated client gets, so it may not
    move when a path moves and may never collide. FastAPI's own derivation does
    both."""
    assert sorted(OPERATIONS) == sorted(ROUTES)


def test_every_operation_is_tagged_with_the_app_that_serves_it():
    wrong = {
        operation_id: operation["tags"]
        for operation_id, operation in OPERATIONS.items()
        if operation["tags"] != [ROUTES[operation_id].endpoint.__module__.split(".")[0]]
    }

    assert wrong == {}


def test_no_component_name_carries_a_module_path():
    """FastAPI resolves two models of one name by putting the module path into the
    component name, so a file that moves renames a symbol in every generated
    client with no field having changed."""
    collided = [name for name in DOCUMENT["components"]["schemas"] if "__" in name]

    assert collided == []


def test_the_document_never_publishes_the_validation_shape_fastapi_injects():
    """ADR-0007 replaced FastAPI's validation handler: a validation failure here is
    `400 invalid_request` with the envelope, and `422` is never used."""
    rendered_document = json.dumps(DOCUMENT)

    assert INJECTED_VALIDATION_STATUS not in {
        status for operation in OPERATIONS.values() for status in operation["responses"]
    }
    for component in INJECTED_VALIDATION_COMPONENTS:
        assert component not in rendered_document


def test_the_document_generates_with_no_warning():
    """A fresh application, because the composed one has already cached its
    document and a second generation would raise nothing whatever the routes say."""
    from api.app import create_app

    with warnings.catch_warnings(record=True) as raised:
        warnings.simplefilter("always")
        create_app(django_asgi_app).openapi()

    assert [str(warning.message) for warning in raised] == []


JSON_MEDIA = "application/json"


def string_schemas(node, name=None):
    """Every string-typed schema the JSON surface declares, with the property name
    that introduced it. A plain recursive walk: a format may sit under a property,
    a list item, a nullable `anyOf` branch, a parameter or a media type, and
    reading those by position would miss whichever shape moves next.

    The multipart body of the upload route is skipped. Its `blob` part is the one
    field of this API that travels as bytes rather than as base64 text, so it
    carries `binary` where every JSON `blob` carries none, and that difference is
    the contract rather than a drift in it.
    """
    if isinstance(node, dict):
        if node.get("type") == "string" and name is not None:
            yield name, node
        for key, value in node.items():
            if key == "properties" and isinstance(value, dict):
                for field, schema in value.items():
                    yield from string_schemas(schema, field)
            elif key == "parameters" and isinstance(value, list):
                for parameter in value:
                    yield from string_schemas(
                        parameter.get("schema", {}), parameter["name"]
                    )
            elif key == "content" and isinstance(value, dict):
                yield from string_schemas(value.get(JSON_MEDIA, {}), name)
            else:
                yield from string_schemas(value, name)
    elif isinstance(node, list):
        for item in node:
            yield from string_schemas(item, name)


FORMATS = {}
for _name, _schema in string_schemas(DOCUMENT):
    FORMATS.setdefault(_name, set()).add(_schema.get("format"))


@pytest.mark.parametrize("field", sorted(FORMATS))
def test_a_field_name_carries_one_format_wherever_it_appears(field):
    """A `device_id` a route takes and a `device_id` a route returns are the same
    value, so a generated client may not get `UUID` on one and `String` on the
    other. One name, one declared format, request side and response side alike."""
    assert FORMATS[field] == {next(iter(FORMATS[field]))}, (
        f"{field} is declared with {sorted(str(f) for f in FORMATS[field])}"
    )


@pytest.mark.parametrize(
    "field", sorted(name for name in FORMATS if name.endswith("_date"))
)
def test_every_date_field_declares_the_date_format(field):
    """Every `_date` on this surface is a `DateField`, so it is a calendar day and
    never a timestamp. Declared as a bare string a client reads it as free text."""
    assert FORMATS[field] == {"date"}, field


def test_the_generator_is_a_pure_function_of_the_tree():
    """Two calls, one document. The drift gate compares bytes, so a generator
    that varied between calls would fail the check on a tree nobody changed."""
    assert rendered() == rendered()


class TestTheDriftCommand:
    """`manage.py openapi`, driven with `BASE_DIR` pointed at a directory of the
    test's own.

    The command writes `settings.BASE_DIR / "openapi.json"`, which in this
    repository is the committed artefact every client generates from — so a test
    that let it write there would rewrite the contract as a side effect of running
    the suite, and `test_the_committed_artefact_is_the_generated_document` above
    would then pass whatever the routes did.
    """

    def test_the_command_writes_the_document_and_says_so(self, tmp_path):
        out = StringIO()

        with override_settings(BASE_DIR=tmp_path):
            call_command("openapi", stdout=out)

        assert (tmp_path / ARTEFACT).read_text(encoding="utf-8") == rendered()
        assert f"wrote {ARTEFACT}" in out.getvalue()

    def test_the_check_passes_on_the_document_the_command_just_wrote(self, tmp_path):
        out = StringIO()

        with override_settings(BASE_DIR=tmp_path):
            call_command("openapi", stdout=out)
            call_command("openapi", "--check", stdout=out)

        assert f"{ARTEFACT} matches the generated document" in out.getvalue()

    def test_the_check_fails_when_the_artefact_has_drifted(self, tmp_path):
        (tmp_path / ARTEFACT).write_text('{"openapi": "3.1.0"}\n', encoding="utf-8")

        with override_settings(BASE_DIR=tmp_path):
            with pytest.raises(CommandError) as raised:
                call_command("openapi", "--check")

        assert "manage.py openapi" in str(raised.value)

    def test_the_check_fails_when_the_artefact_is_missing_entirely(self, tmp_path):
        """A deleted file is drift too. Reading a missing path would be an
        `OSError` with a traceback rather than the sentence that says what to run.
        """
        with override_settings(BASE_DIR=tmp_path):
            with pytest.raises(CommandError) as raised:
                call_command("openapi", "--check")

        assert ARTEFACT in str(raised.value)
        assert not (tmp_path / ARTEFACT).exists()

    def test_a_failed_check_never_prints_the_document_it_compared(self, tmp_path):
        """A schema dumped into a CI log is a route map in a place nobody
        controls. The reader regenerates and reads the diff in their own tree."""
        (tmp_path / ARTEFACT).write_text("{}\n", encoding="utf-8")

        with override_settings(BASE_DIR=tmp_path):
            with pytest.raises(CommandError) as raised:
                call_command("openapi", "--check")

        message = str(raised.value)
        for path in sorted(DOCUMENT["paths"])[:5]:
            assert path not in message

    def test_the_check_writes_nothing_at_all(self, tmp_path):
        """`--check` is what CI runs, and a check that repaired the drift it found
        would report success on a tree that was wrong."""
        stale = '{"openapi": "3.1.0"}\n'
        (tmp_path / ARTEFACT).write_text(stale, encoding="utf-8")

        with override_settings(BASE_DIR=tmp_path):
            with pytest.raises(CommandError):
                call_command("openapi", "--check")

        assert (tmp_path / ARTEFACT).read_text(encoding="utf-8") == stale

    def test_writing_twice_produces_one_file(self, tmp_path):
        """The stable key order, at the level the gate reads it: bytes on disk."""
        with override_settings(BASE_DIR=tmp_path):
            call_command("openapi", stdout=StringIO())
            first = (tmp_path / ARTEFACT).read_bytes()
            call_command("openapi", stdout=StringIO())

        assert (tmp_path / ARTEFACT).read_bytes() == first
