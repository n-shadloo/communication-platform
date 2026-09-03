# 0003. One ASGI process

- Status: Accepted
- Phase: 2
- Date: 2026-09-03

## Context

Production is one VPS with 1 vCPU and 1 GB RAM. PostgreSQL, Redis, LiveKit,
coturn and nginx already share it. Two application process trees — one for the
API and one for the admin — would need a second systemd unit, a second nginx
route and a second copy of the interpreter's resident memory.

[0002](0002-fastapi-as-the-only-http-api-surface.md) puts FastAPI in front and
keeps Django for the ORM, the migrations and the admin. Both must be reachable,
and the Django app registry must be populated before any model is imported.

## Decision

FastAPI is the root ASGI application. The Django ASGI application is mounted at
`ADMIN_PATH` for the admin and, in development only, for static files.
`django.setup()` runs before any model import.

uvicorn serves the process with uvloop, httptools and the `websockets` protocol
implementation. systemd supervises uvicorn directly. The worker count comes from
`WEB_CONCURRENCY`, default 1. No Gunicorn. No Daphne.

## Position fields

- **Forcing function.** 1 vCPU and 1 GB RAM will not hold two process trees, and
  a second port would need a second nginx route and a second unit.
- **Scale band.** Band 0, holding through band 1. `WEB_CONCURRENCY` is the lever
  that carries it there.
- **Flip trigger.** Admin traffic and API traffic contend for the same worker, or
  the admin needs a restart cadence the API cannot take.
- **Cost.** One process is one blast radius. An admin request that blocks a
  worker blocks the API, and one crash takes both surfaces down. Import order
  becomes load-bearing: a model imported before `django.setup()` fails at boot.
- **Evidence.** uvicorn is the reference ASGI server, documents the uvloop and
  httptools extras, and documents being supervised directly by a process manager.
  Gunicorn with uvicorn workers exists for multi-worker deployments that need a
  master process; at one worker it adds a process for nothing. **Currency:**
  current.

## Consequences

- `daphne` leaves `requirements/prod.txt`. `ops/systemd/chat.service` changes its
  `ExecStart` from daphne to uvicorn, and `--access-log` becomes
  `--no-access-log` per [0014](0014-process-hardening-at-the-edge.md).
- The admin lives under `ADMIN_PATH`, which nginx must route to the same
  upstream. The API origin and the admin origin are the same origin, which is
  part of why no CORS policy exists.
- Static files are served by Django in development only. In production nginx
  serves `static_root`, and `ProtectSystem=strict` in the unit already lists it
  as a writable path for `collectstatic`.
- Raising `WEB_CONCURRENCY` above 1 multiplies the Redis subscription
  connections of [0004](0004-websocket-gateway-on-redis-pubsub.md), one for each
  worker.
