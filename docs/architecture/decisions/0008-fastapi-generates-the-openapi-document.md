# 0008. FastAPI generates the OpenAPI document

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landed: 2026-09-04, in the last run of phase 2. `python manage.py openapi` writes
  `backend/openapi.json`, `--check` fails on drift, and CI runs it as a job named
  `schema`. The document is complete rather than merely present: every route declares
  a response model for its success status and the envelope for every error status it
  can answer, and `core/tests/test_openapi.py` fails one that does not — which is the
  check FastAPI has no counterpart for, since a route with no model reaches the
  document as an empty schema in silence. The `/openapi.json`, `/docs` and `/redoc`
  routes exist under `DEBUG` and are absent from the application otherwise.

## Context

There is no machine-readable schema today. The per-app `API.md` files are the
only contract, and nothing checks them against the code. A client author reads
prose and hopes it is current.

FastAPI generates an OpenAPI document from the route signatures and the Pydantic
models, so the document costs nothing to produce once
[0002](0002-fastapi-as-the-only-http-api-surface.md) lands. What it costs is a
decision about where the document lives and what stops it drifting.

## Decision

FastAPI generates the OpenAPI document. `python manage.py openapi` writes
`backend/openapi.json`; `--check` fails on drift. CI runs the check.

The interactive documentation routes are closed outside `DEBUG`.

**Superseded in part by [0020](0020-one-android-client-and-no-browser-surface.md).**
The schema route and the two interactive views are now unregistered in every mode,
`DEBUG` included: they render for a browser the product does not have. Generation,
the drift gate and the `API.md` files below are unchanged, and `backend/openapi.json`
is now the only published form of the contract.

The per-app `API.md` files stay the human reference and match the code.

## Position fields

- **Forcing function.** A schema that no gate checks drifts from the code within
  one release, and the client author is the person who discovers it.
- **Scale band.** Band 0 to band 4. The check does not get more expensive with
  traffic.
- **Flip trigger.** The committed document grows large enough that a diff on it
  stops being reviewable, at which point the check moves from "diff in review" to
  "generated artifact compared in CI only".
- **Cost.** One committed artifact to regenerate on every contract change, and
  one more way for a pull request to fail.
- **Evidence.** Generating the schema from the code and checking it in CI is the
  standard defence against contract drift. **Currency:** current.

## Consequences

- `backend/openapi.json` is committed, so a contract change is visible as a diff
  in review rather than only as a code change.
- The `/docs` and `/redoc` routes existed in development only, and after
  [0020](0020-one-android-client-and-no-browser-surface.md) exist nowhere. They
  describe every route and every payload shape, which is reconnaissance on a server
  whose posture is to reveal nothing.
- The `API.md` files stay authoritative for the parts a generated schema cannot
  carry: the retry semantics of [0007](0007-contract-conventions.md), the bucket
  rules, and the close codes.
- The management command lives on the Django side even though FastAPI produces
  the document, because `manage.py` is the one entry point that already runs
  `django.setup()`.
