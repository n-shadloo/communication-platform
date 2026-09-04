# 0002. FastAPI is the only HTTP API surface

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landed: 2026-09-04, over the first three runs of phase 2. FastAPI serves every
  HTTP route of every app, and Django REST Framework is gone from the project. The
  Django ASGI application answers `ADMIN_PATH` and, in development, the static files
  the admin renders with.

## Context

The server runs Django 6.0 with Django REST Framework behind Daphne. The same
process must also hold a long-lived WebSocket connection for every live device.
DRF is a synchronous framework: its view, serializer, permission and throttle
layers were built for a request that occupies a worker for its whole life.

The qualifying condition for a second framework, which doctrine otherwise
refuses, is the long-lived connection plus the developer's stated forcing
function for a faster response path.

## Decision

FastAPI is the only HTTP API surface. Django REST Framework leaves the project.

Django keeps the ORM, the migrations, the admin and the settings.

## Position fields

- **Forcing function.** A long-lived WebSocket connection and a faster response
  path in the same process, stated by the developer as a requirement rather than
  a preference.
- **Scale band.** Band 0, holding through band 2. Below band 1 the choice buys
  little; the decision is taken now because the rewrite is cheapest before a
  client ships.
- **Flip trigger.** The cost of two frameworks in one repository exceeds the
  response-path gain, or Django's own async story closes the gap for the routes
  this system serves.
- **Cost.** The whole view, serializer, permission and throttle layer is
  rewritten. Two request models live in one repository, and a contributor must
  know which one owns a given path. DRF's exception handling, throttling and
  browsable-API conveniences are replaced by explicit code.
- **Evidence.** Django has supported ASGI since 3.0 and documents running an
  ASGI application; FastAPI documents mounting sub-applications and running
  behind one ASGI server. A named production system running this exact
  Django-ORM-behind-FastAPI split is not established here — reasoned, not
  sourced. **Currency:** current.

## Consequences

- `djangorestframework` left `requirements/prod.txt`, and `rest_framework` left
  `INSTALLED_APPS`. `python-multipart` took its place, because Starlette needs it to
  parse the one multipart body this API accepts.
- Every `REST_FRAMEWORK` setting lost its meaning and was replaced: the
  authentication class by a FastAPI dependency, the permission classes by
  dependencies, the throttle rates by [0010](0010-redis-rate-limiting-that-fails-closed.md),
  the exception handler by [0007](0007-contract-conventions.md). `THROTTLE_RATES` is
  the one table that survived the block, because the Redis limiter reads it.
- The per-app `API.md` files stay the human reference and are now written against
  the FastAPI routes. `API_CHANGES.md` records every contract change of the move.
- `fastapi-alongside-django` owns the code on the FastAPI side and the seam. This
  ADR only records that the surface exists.
