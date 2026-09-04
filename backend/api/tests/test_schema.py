"""What each route declares into the OpenAPI document, and what is taken back out.

`core/tests/test_openapi.py` is the completeness gate over the real document: it
walks every operation and fails one whose declared set is short. This file covers
the three pieces that gate stands on — the `responses` builder, the operation
identifier, and the removal of the validation response FastAPI injects — driven on
an application built here, because the composed one has cached its document and a
second generation would prove nothing.
"""

import pytest
from fastapi import FastAPI
from pydantic import BaseModel

from api import schema
from api.schema import (
    INJECTED_VALIDATION_COMPONENTS,
    INJECTED_VALIDATION_STATUS,
    UNIVERSAL,
    VOCABULARY,
    ErrorOut,
    errors,
    operation_id,
)

ENVELOPE = "#/components/schemas/ErrorOut"


class Payload(BaseModel):
    name: str


def application():
    """A route with a body and a path parameter: the shape FastAPI injects its
    own validation response into."""
    app = FastAPI(generate_unique_id_function=operation_id)

    @app.post("/things/{thing_id}", responses=errors("not_found", "invalid_request"))
    async def replace_a_thing(thing_id: int, payload: Payload):
        return {"name": payload.name}

    return app


class TestTheResponsesBuilder:
    def test_a_route_that_declares_nothing_still_answers_the_universal_two(self):
        """An unhandled failure and the request deadline belong to every route,
        so they are added here rather than repeated on thirty-two routes."""
        declared = errors()

        assert set(declared) == {VOCABULARY[code] for code in UNIVERSAL}
        assert set(UNIVERSAL) == {"server_error", "unavailable"}

    def test_every_status_carries_the_envelope_and_names_its_codes(self):
        declared = errors("not_found")

        assert declared[404] == {"model": ErrorOut, "description": "`not_found`"}

    def test_two_codes_of_one_status_are_described_together(self):
        """`400` is two different refusals with two different details, and a
        client reading the document has to be able to tell which it will get."""
        declared = errors("invalid_request", "bad_bucket")

        assert set(declared) == {400, 500, 503}
        assert declared[400]["description"] == "`invalid_request`, `bad_bucket`"

    def test_a_code_outside_the_vocabulary_cannot_be_declared(self):
        """The error path, and it fires at import time: a route that invents a
        code fails the application before it ever serves a request."""
        with pytest.raises(KeyError):
            errors("teapot")

    def test_the_envelope_model_is_the_one_the_handlers_render(self):
        """`detail` is a string on every code but `invalid_request`, where it is
        a field path to the messages that failed."""
        assert ErrorOut(code="not_found", detail="No such route or resource.")
        assert ErrorOut(code="invalid_request", detail={"username": ["too short"]})
        with pytest.raises(ValueError):
            ErrorOut(code="invalid_request", detail={"username": "not a list"})


class TestTheOperationIdentifier:
    def test_the_identifier_is_the_handler_name(self):
        """FastAPI's own derivation builds it from the name, the path and one
        method out of an unordered set, so it moves when a path moves."""
        app = application()
        document = app.openapi()

        assert document["paths"]["/things/{thing_id}"]["post"]["operationId"] == (
            "replace_a_thing"
        )

    def test_the_identifier_does_not_move_when_the_path_does(self):
        app = FastAPI(generate_unique_id_function=operation_id)

        @app.post("/somewhere/else")
        async def replace_a_thing(payload: Payload):
            return {}

        moved = app.openapi()["paths"]["/somewhere/else"]["post"]["operationId"]

        assert (
            moved
            == application().openapi()["paths"]["/things/{thing_id}"]["post"][
                "operationId"
            ]
        )


class TestTheInjectedValidationResponse:
    def test_fastapi_injects_it_before_the_customisation_is_installed(self):
        """Guards the guard below: without this, a document that never carried a
        `422` would pass the removal test for the wrong reason."""
        generated = application().openapi()

        assert (
            INJECTED_VALIDATION_STATUS
            in generated["paths"]["/things/{thing_id}"]["post"]["responses"]
        )
        for component in INJECTED_VALIDATION_COMPONENTS:
            assert component in generated["components"]["schemas"]

    def test_the_installed_generator_removes_the_status_and_its_components(self):
        """ADR-0007: a validation failure on this surface is `400 invalid_request`
        with the envelope. Left in, the document would publish a status no route
        returns and a body shape no client will ever receive."""
        app = application()
        schema.install(app)

        generated = app.openapi()

        responses = generated["paths"]["/things/{thing_id}"]["post"]["responses"]
        assert INJECTED_VALIDATION_STATUS not in responses
        for component in INJECTED_VALIDATION_COMPONENTS:
            assert component not in generated["components"]["schemas"]

    def test_what_the_route_itself_declared_survives_the_removal(self):
        """The removal is by status, so a route that declares `400` keeps it."""
        app = application()
        schema.install(app)

        responses = app.openapi()["paths"]["/things/{thing_id}"]["post"]["responses"]

        assert set(responses) >= {"200", "400", "404", "500", "503"}
        assert responses["400"]["content"]["application/json"]["schema"]["$ref"] == (
            ENVELOPE
        )

    def test_the_document_is_generated_once_and_then_served_from_the_cache(self):
        """`/docs`, `manage.py openapi` and the drift gate all read this, so a
        second generation would let two of them disagree."""
        app = application()
        schema.install(app)

        assert app.openapi() is app.openapi()

    def test_a_document_with_no_components_at_all_is_left_alone(self):
        """The rare case: an application whose routes take no model has no
        `components` key, and the removal must not build one."""
        app = FastAPI(generate_unique_id_function=operation_id)

        @app.get("/ping")
        async def ping():
            return None

        schema.install(app)

        generated = app.openapi()

        assert "components" not in generated
        assert set(generated["paths"]) == {"/ping"}
