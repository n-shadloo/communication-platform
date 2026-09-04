# 0005. The Django ORM is the only data access layer

- Status: Accepted
- Phase: 2
- Date: 2026-09-03
- Landing: 2026-09-04, in the first run of phase 2. `CONN_MAX_AGE` is 0 with the
  psycopg pool, and every FastAPI unit of work runs through the bracket inside a
  per-request `ThreadSensitiveContext`. The WebSocket path still runs on Channels'
  own helper.

## Context

[0002](0002-fastapi-as-the-only-http-api-surface.md) puts an async framework in
front of a synchronous ORM. That seam has to be decided explicitly, because the
failure mode is silent: an ORM call on the event loop either raises
`SynchronousOnlyOperation` or, worse, blocks every other connection on the
process for the duration of the query.

The alternative is a second data access layer — SQLAlchemy against the same
tables. That would need its own model of the schema, kept in step with the
migrations by hand, and its own audit against `core/tests/test_seizure_guard.py`
and `test_manifest.py`, which read the Django model metadata to prove that no
forbidden column exists.

## Decision

The Django ORM is the only data access layer.

Every database unit of work is one synchronous function that opens its
transaction inside itself and never awaits. `sync_to_async` with
`thread_sensitive=True` runs it. Each HTTP request and each WebSocket connection
runs inside its own asgiref `ThreadSensitiveContext`. `close_old_connections()`
brackets each unit on the ORM thread. `CONN_MAX_AGE` is 0, and Django's psycopg
connection pool removes the connection setup cost.

The worker count is the concurrency lever.

## Position fields

- **Forcing function.** A second data access layer would need its own schema
  model and its own audit against the seizure guard, which reads Django model
  metadata.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** The ORM thread pool saturates before the database does, and
  a profile names the thread hop — not the query — as the top cost.
- **Cost.** Every database call costs a thread hop. A unit of work cannot await,
  so a transaction can never span an external call, which is a constraint on how
  handlers are written rather than an inefficiency.
- **Evidence.** This is the execution model Django's own async views use to
  reach the ORM, and `ThreadSensitiveContext` is asgiref's documented API for
  scoping the thread that runs them. Django's psycopg connection pool is
  documented from Django 5.1. **Currency:** current.

## Consequences

- `CONN_MAX_AGE` moves from 60 to 0. Persistent connections and a pool solve the
  same problem twice, and at `WEB_CONCURRENCY=1` the pool is the one that
  survives a worker restart.
- A handler that needs two units of work gets two `sync_to_async` calls and two
  transactions. Anything that must be atomic across both belongs in one unit.
- `thread_sensitive=True` means one shared executor: two units of work in the
  same context run in sequence, never in parallel. That is what makes the
  transaction semantics predictable, and it is also the ceiling the flip trigger
  watches.
- `django-performance-optimizer` owns any measurement of that ceiling. This ADR
  fixes only the execution model.
