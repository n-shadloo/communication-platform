# 0007. Contract conventions

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landing: 2026-09-04, in the first run of phase 2. The envelope, the `400`
  validation status, the logout change and the `username_taken` status hold on every
  route FastAPI serves. A path no route serves at all still answers Django's own
  `404` page.

## Context

Rewriting the HTTP surface on FastAPI, per
[0002](0002-fastapi-as-the-only-http-api-surface.md), replaces DRF's defaults for
error shape, validation failure, pagination and status codes. FastAPI's own
defaults differ from DRF's — most visibly, a validation failure answers `422`
with a nested error list. A client written against the current contract would
break on that alone.

The client is not released. `frontend/` has no chat, group or voice feature yet.
That is the window in which a contract can be fixed cheaply, and it closes when
the first client ships.

## Decision

One error envelope `{"code": ..., "detail": ...}` on every error, including
`404`, `405`, `413`, `429` and `500`. Validation failures answer `400` with code
`invalid_request` and a field-located detail that never echoes input. `422` is
never used.

The versioning strategy is the URL path. The version stays `v1` because no
released client exists and no consumer needs a deprecation cycle; every breaking
change is listed in `API_CHANGES.md`.

Pagination is keyset only, on the two routes that page today. No filtering
parameter exists. No idempotency store exists, because a stored response for a
send would link a sender to its recipients at rest; every mutating route
documents its retry semantics instead.

`POST /auth/logout` takes no body and answers `204`. `username_taken` answers
`409`.

## Position fields

- **Forcing function.** A stored response for a send would link a sender to its
  recipients at rest, which is exactly what the schema refuses to hold. The
  error shape follows from there: one envelope a client can branch on without
  parsing prose.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** A released client exists that cannot be updated in step with
  the server. The version then needs a real deprecation cycle, and `v2` becomes a
  path rather than a note in `API_CHANGES.md`.
- **Cost.** A retried send can duplicate an envelope, and the client must
  tolerate that. Never echoing input in a validation error makes some failures
  harder to debug from the response alone.
- **Evidence.** Keyset pagination is the standard cursor form for a collection
  that grows while a client reads it. The refusal of an idempotency store is a
  consequence of this system's threat model rather than general practice —
  reasoned, not sourced. **Currency:** current.

## Consequences

- FastAPI's `RequestValidationError` handler must be replaced, or every
  validation failure answers `422` with a body no client expects.
- Every mutating route documents what a retry does. That text is part of the
  contract and belongs in the per-app `API.md`.
- `API_CHANGES.md` becomes load-bearing: with the version frozen at `v1`, it is
  the only record a client author has of a breaking change.
- `django-api-contract` owns the mechanics of a change to a route. This ADR fixes
  the conventions those changes must satisfy.
