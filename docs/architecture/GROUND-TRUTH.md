# Ground truth — the measured facts of this deployment

Every entry below carries the date its measurement ran. **Re-verify any entry
older than 90 days.** An entry past that window is a claim, not a fact; re-verify
it or delete it, and never lengthen the window to bring one back inside it.

Scope note, and the reason several sections are thin: the VPS does not serve yet.
The system is at scale band 0, pre-launch, with no real traffic and no production
database. Every entry here was measured on the repository at commit `32617e7` or
on the developer machine. A row that names the VPS states what the committed
operator configuration sets, not what a running host reports, and says so. The
first production measurement replaces it.

Decisions, rationale and rejected alternatives live in
[`DESIGN-RECORD.md`](DESIGN-RECORD.md) and in [`decisions/`](decisions/). This
file holds no decision.

## 1. Topology

| Component | Where it runs | What it reaches | verified |
|---|---|---|---|
| nginx | VPS, ports 80 and 443, TLS 1.3 only, `ssl_early_data off` | `127.0.0.1:8000` for `/api/` and `/ws`, `127.0.0.1:7880` for `/rtc` | 2026-09-03 (configured, `backend/ops/nginx/chat.nimashadloo.dev.conf`) |
| ASGI application | VPS, uvicorn on `127.0.0.1:8000`, systemd unit `chat.service` (writes `media_root` and nothing else, `LimitNOFILE` 4096, `--limit-concurrency` 1024), user `deploy`, `WEB_CONCURRENCY` workers (default 1), uvloop and httptools, the `websockets` sans-io implementation. In-process: FastAPI is the root application for every scope — every API route, the `/ws` gateway, and the Django ASGI application answering `ADMIN_PATH` alone | PostgreSQL and Redis on loopback | 2026-09-04 (configured, `backend/ops/systemd/chat.service`; composition observed in `backend/config/asgi.py`) |
| PostgreSQL 16 | VPS, loopback | — | 2026-09-03 (configured) |
| Redis 7 | VPS, loopback, `bind 127.0.0.1`, `protected-mode yes`, `requirepass` set at deploy time — `check --deploy` refuses a `REDIS_URL` without a password (`core.E004`) | — | 2026-09-04 (configured, `backend/ops/redis/redis-chatapp.conf`; the check in `backend/core/checks.py`) |
| LiveKit SFU | VPS, `127.0.0.1:7880`, RTC UDP 50100–50200, TCP 7881, `turn.enabled: false`, `use_external_ip: false` | the participants' media | 2026-09-03 (configured, `backend/ops/livekit/livekit.yaml`) |
| coturn | VPS, 3478 and 5349, relay ports 50300–50400, `use-auth-secret`, `no-stun` | the participants' media | 2026-09-03 (configured, `backend/ops/coturn/turnserver.conf`) |
| Maintenance job | VPS, systemd timer `chat-maintenance.timer` | PostgreSQL | 2026-09-03 (configured, `backend/ops/systemd/`) |
| Developer machine | macOS, PostgreSQL 16 and Redis 7 native on loopback, venv at `backend/.venv` | — | 2026-09-03 (observed) |

The deployment root on the VPS is `/srv/chat`. The application working directory
is `/srv/chat/backend`. There is no second application host, no load balancer, no
CDN, no external push service, no external STUN, and no third-party API on the
runtime path.

## 2. Deviations from a default configuration

| Setting | The value here | The default | The ADR that decided it | verified |
|---|---|---|---|---|
| `WSGI_APPLICATION` | `None` | the generated `config.wsgi.application` | — (ASGI-only since inception) | 2026-09-03 |
| `AUTH_USER_MODEL` | `accounts.User` | `auth.User` | — (set at inception; a one-way door) | 2026-09-03 |
| `PASSWORD_HASHERS[0]` | `Argon2PasswordHasher` | `PBKDF2PasswordHasher` | — | 2026-09-03 |
| `AUTH_PASSWORD_VALIDATORS` | minimum length 10, common-password check only | four validators, minimum length 8 | — | 2026-09-03 |
| `DB_CONN_MAX_AGE` | 0 | 0 | [0005](decisions/0005-django-orm-on-a-thread-sensitive-data-path.md) | 2026-09-04 |
| `DATABASES["default"]["OPTIONS"]["pool"]` | `{min_size: 1, max_size: 16, timeout: 10}` | no pool | [0005](decisions/0005-django-orm-on-a-thread-sensitive-data-path.md) | 2026-09-04 |
| FastAPI `openapi_url`, `docs_url`, `redoc_url` | their defaults under `DEBUG`, `None` otherwise, so the three routes — and the `/docs/oauth2-redirect` route FastAPI adds beside them — are absent from the application in production | `/openapi.json`, `/docs`, `/redoc`, always registered | [0008](decisions/0008-fastapi-generates-the-openapi-document.md) | 2026-09-04 |
| FastAPI `generate_unique_id_function` | the route's handler name | the route name, the path and one method taken from an unordered set | [0008](decisions/0008-fastapi-generates-the-openapi-document.md) — the default moves a client's method name when a path moves, and gives one identifier to both operations of a two-method route | 2026-09-04 |
| The `422` FastAPI declares on every route that takes a parameter | removed from the generated document, with the two components only it referenced | declared, referencing `HTTPValidationError` | [0007](decisions/0007-contract-conventions.md) replaced the validation handler, so no route can produce that body | 2026-09-04 |
| FastAPI `router.redirect_slashes` | `False` | `True` | [0007](decisions/0007-contract-conventions.md) | 2026-09-04 |
| FastAPI `router.default` | a dispatcher that hands `ADMIN_PATH` (and `STATIC_URL` under `DEBUG`) to the Django ASGI application and raises the router's own 404 for everything else | Starlette's own 404 | [0002](decisions/0002-fastapi-as-the-only-http-api-surface.md) | 2026-09-04 |
| Multipart limits on the upload route | `max_files=1`, `max_fields=0`, and a spool threshold of 64 KiB, set by parsing the form in the route rather than declaring an `UploadFile` parameter | `max_files=1000`, `max_fields=1000`, and a spool threshold of 1 MiB | [0014](decisions/0014-process-hardening-at-the-edge.md) | 2026-09-04 |
| Access log | `--no-access-log` on uvicorn, and the `uvicorn`, `uvicorn.error`, `uvicorn.access`, `websockets` and `push_response` loggers claimed in `LOGGING` at WARNING with `propagate: False` | an access log is written, and redis-py installs a stdout `StreamHandler` for `push_response` | — (invariant: no identifier reaches a log line) | 2026-09-04 |
| WebSocket push handler on every `PubSub` the bus opens | `realtime.bus._keep`, which returns the push unchanged | redis-py's own, which logs the topic and the payload at DEBUG and installs the stdout handler above | — (invariant: no identifier, and no blob, reaches a log line) | 2026-09-04 |
| `ThreadSensitiveContext` on a WebSocket scope | not entered; every socket's ORM work shares one executor thread | a context per connection, and therefore a thread per connection | [0005](decisions/0005-django-orm-on-a-thread-sensitive-data-path.md) | 2026-09-04 |
| Redis persistence | `save ""`, `appendonly no` | RDB snapshots on | — (invariant: volatile data never touches disk) | 2026-09-03 |
| `CACHES` | Django's default, `LocMemCache`, which nothing in the project uses | the same default, but a Redis-backed cache is the usual choice when Redis is already present | [0018](decisions/0018-redis-is-authenticated-and-never-deserialized.md) — every built-in cache backend unpickles what it reads, and Redis is writable by every local process | 2026-09-04 |
| `SESSION_COOKIE_NAME`, `CSRF_COOKIE_NAME` (production) | `__Host-sessionid`, `__Host-csrftoken` | `sessionid`, `csrftoken` | — (the VPS serves two other projects; a `__Host-` cookie cannot be set by a sibling site or shadowed by a broader one) | 2026-09-04 |
| `ssl_early_data` | `off` | `off` in nginx, but commonly turned on with TLS 1.3 | — (0-RTT payloads are replayable) | 2026-09-03 |
| `client_max_body_size` | 70m | 1m | — (the largest attachment bucket is 64 MiB; the application caps the upload route tighter still, at that bucket plus 8 KiB of multipart wrapper) | 2026-09-04 |
| `ssl_protocols` | `TLSv1.3` | `TLSv1.2 TLSv1.3` | — | 2026-09-03 |
| LiveKit `turn.enabled` | `false` | `false`, but the bundled TURN is the common choice | — (coturn is the relay) | 2026-09-03 |
| coturn `no-stun` | set | STUN is served | — (relay-only; no discovery surface) | 2026-09-03 |
| `ruff` line length | 90 | 88 | [0013](decisions/0013-pytest-and-ruff-as-the-test-and-lint-stack.md) | 2026-09-03 |

## 3. Scale facts

| Object | The number | How the measurement ran | verified |
|---|---|---|---|
| Python | 3.12.10 | `backend/.venv/bin/python -V` | 2026-09-03 |
| Django | 6.0.7 | `django.get_version()` | 2026-09-03 |
| FastAPI / Starlette / Pydantic | 0.141.1 / 1.6.0 / 2.13.5 | `requirements/prod.txt` | 2026-09-04 |
| PyJWT / psycopg-pool / python-multipart | 2.13.0 / 3.3.1 / 0.0.32 | `requirements/prod.txt` | 2026-09-04 |
| uvicorn / uvloop / httptools / websockets | 0.52.4 / 0.22.1 / 0.8.0 / 17.1 | `requirements/prod.txt` | 2026-09-04 |
| redis-py | 8.0.1 | `requirements/prod.txt` | 2026-09-04 |
| httpx, cryptography (test only) | 0.28.1, 49.0.0 | `requirements/dev.txt` | 2026-09-04 |
| Pinned production distributions | 30, down from 42 when Channels, daphne and the sixteen packages only they pulled in left. The row read 29 before this run and was off by one against the command beside it | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/prod.txt` | 2026-09-04 |
| Pinned development distributions | 13 | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/dev.txt` | 2026-09-04 |
| Project apps | 8 — `core`, `accounts`, `devices`, `vault`, `messaging`, `attachments`, `voicerooms`, `realtime` | `INSTALLED_APPS` | 2026-09-03 |
| Project models | 11 | `django.apps.apps.get_models()` filtered to the project apps | 2026-09-03 |
| Migration files | 7 — one `0001_initial` for each app that owns a table, per [0009](decisions/0009-regenerate-the-initial-migrations.md), plus `messaging.0002_index_the_retention_filter`, the first migration of the append-only era | `git ls-files 'backend/*/migrations/0*.py' \| wc -l`. Run over the working tree instead and `backend/.venv` adds 23 of Django's own | 2026-09-04 |
| Tracked Python files | 189 | `git ls-files '*.py' \| wc -l` | 2026-09-04 |
| Test files | 74 | `git ls-files '*/test_*.py' \| wc -l` | 2026-09-04 |
| Tests collected | 1225, plus 48 subtests. The rise over 1172 is the phase-4 performance, background-work and migration audits: every fix landed with the test that failed before it, plus the query counts of the routes that had none, the migration lock-class gates, and the recovery paths — a dropped subscriber connection, a cancelled socket, a crashed one | `pytest -q` | 2026-09-04 |
| The OpenAPI document | 32 operations over 27 paths, 52 components, 120 716 bytes at `backend/openapi.json` | `python manage.py openapi`, then `wc -c` | 2026-09-04 |
| URL routes declared | 1 `path()` entry across the `urls.py` files — the admin — plus `staticfiles_urlpatterns()` under `DEBUG`, 32 FastAPI method-and-path pairs over 27 distinct paths, and one WebSocket route at `/ws` with no HTTP method. Under `DEBUG` only, FastAPI adds four of its own: `/openapi.json`, `/docs`, `/docs/oauth2-redirect` and `/redoc` | `grep -rhn "path(" --include='urls.py' . \| wc -l`, and `core/tests/test_route_table.py` for the FastAPI table | 2026-09-04 |
| Project apps | `api/` is a Python package and not an installed app: it holds no model and appears in no `INSTALLED_APPS` | `INSTALLED_APPS` | 2026-09-04 |
| Production hardware | 1 vCPU, 1 GB RAM, single VPS | operator statement; no host metric exists yet | 2026-09-03 |
| Accounts, devices, groups | 0 accounts in production; the band caps the design at fewer than 50 accounts, at most 10 devices for each account, and at most 50 members in a group | pre-launch; the caps are the stated scale band, not a measurement | 2026-09-03 |
| Scale band | Band 0, pre-launch | no production traffic exists | 2026-09-03 |

The row-count rows a live deployment would carry do not exist yet. Read the
absence of a number as unknown, never as small: `messaging.QueuedEnvelope` is the
table whose size follows traffic, and nothing has measured it.

## 4. Measured operations

| Operation | The duration | The conditions of the run | verified |
|---|---|---|---|
| Full test suite | 48.8 s, 1225 passed, 48 subtests | Developer machine, `pytest -q`, native PostgreSQL 16 and Redis 7 on loopback, random order (`pytest-randomly` seed reported per run) | 2026-09-04 |
| Full test suite, second order | 48.5 s, 1225 passed, 48 subtests | Same machine, a different `pytest-randomly` order in the same session. The spread between the two orders is the cost of the `transaction=True` tests, whose table truncation lands in a different place each run | 2026-09-04 |
| Gateway suite against a real Redis bus | 8.5 s, 69 passed | Developer machine, `pytest realtime/ -q -p no:randomly`. Every socket test drives the composed ASGI application on the test's own event loop and fans out through Redis publish and subscribe; three of them run a real uvicorn on an ephemeral port | 2026-09-04 |
| The regenerated migration history against the one it replaced | The same schema: 104 columns, 47 indexes and 61 constraints, identical name for name and definition for definition. The one difference is the physical column order of `devices_device`, where the four columns the old history appended now sit in model order | Both histories applied to a scratch database of their own on the developer machine, then `information_schema.columns`, `pg_indexes` and `pg_constraint` dumped from each and diffed. The `AddField` for `Device.refresh_generation` this row used to time is part of `devices.0001_initial` now and no longer runs against a populated table | 2026-09-04 |
| Every `0001_initial`, forward and back | Every statement is a `CREATE TABLE`, a `CREATE INDEX` or an `ALTER TABLE … ADD CONSTRAINT` against a relation the same migration created, so each ACCESS EXCLUSIVE lock is on a relation no other session can name. Every app reaches `zero` again, `accounts` cascading through `admin` on the way | `python manage.py sqlmigrate <app> 0001` read statement by statement, and `core/tests/test_migrations.py` for the replay | 2026-09-04 |
| `messaging.0002_index_the_retention_filter` | One statement, `CREATE INDEX CONCURRENTLY "ix_queue_queued_hour" ON "messaging_queuedenvelope" ("queued_hour")`, which takes SHARE UPDATE EXCLUSIVE and blocks neither reads nor writes. The migration is `atomic = False`, and its SQL carries no `BEGIN`. The index is 1544 kB at 200 000 rows | `python manage.py sqlmigrate messaging 0002`, and `core/tests/test_migrations.py`, which reads the same output against the recorded lock class | 2026-09-04 |
| Test-database teardown | warns on roughly one run in three: `database "test_chatapp" is being accessed by other users`, one session | Developer machine, `pytest -q` repeated. It is a teardown warning and never a failure; the suite is green either way, and CI is unaffected because each run builds a fresh database. Reproduced with `DB_POOL_MIN_SIZE=0`, so it is not the pool's idle connection but a connection a worker thread still holds when `destroy_test_db` runs | 2026-09-04 |
| Send fan-out | 4 queries of its own, at 1, 6 and 20 recipients alike, and 4 for ten envelopes to one mailbox: one locked liveness read, one aggregate of the undelivered bytes each target holds (the mailbox ceiling), one bulk counter update, one bulk insert. A batch that reaches only stale devices costs the liveness read alone. The authentication dependency adds one query to every route | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `messaging/tests/test_query_counts.py` | 2026-09-04 |
| Prekey claim | 1 target read, 1 locked select per target device, and 1 delete for the batch — 3 queries of its own for one device with a pool of 1, 20 or 200 keys, and 8 for six devices. An exhausted pool costs one less, because nothing is deleted | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `devices/tests/test_query_counts.py` | 2026-09-04 |
| Attachment upload | 3 queries of its own — the uploader's row lock, one `SUM` aggregate, one insert — at 0 and at 25 attachments already held. The download is 1. The authentication dependency adds one query to every route | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `attachments/tests/test_query_counts.py` | 2026-09-04 |
| Offline install of the regenerated set | 54 hash-verified wheels collected and installed with `--no-index` | `pip download --require-hashes --only-binary=:all: -r requirements/dev.txt`, then `pip install --no-index --find-links` into a fresh venv, on the developer machine | 2026-09-04 |
| Hash-verified dependency install | 7 s to fetch and install the two added wheels | `pip install --require-hashes -r requirements/dev.txt` on the developer machine, online | 2026-09-03 |

| Retention sweep, 99 962 expired envelopes of 200 000 | 5.95 s wall, 100 batches of 1000 | `time manage.py prune` against the seeded copy below. Includes interpreter and Django start-up | 2026-09-04 |
| Retention sweep, nothing expired | 0.33 s wall, almost all of it interpreter and Django start-up. The envelope probe itself is 2 buffers and 0.027 ms | The same command against the same copy with nothing past its TTL | 2026-09-04 |
| Live push of one maximum batch | 131 ms of event-loop CPU: `json.dumps` of 256 payloads carrying a 349 528-character base64 blob each. The 53 ms of `base64.b64encode` that used to precede it is gone — the string the sender sent is handed through instead — and the 256 publishes are one pipelined round trip rather than 37.1 ms of sequential ones | `time.perf_counter` around the encode-and-serialize loop, 256 × the 262 144 bucket, on the developer machine | 2026-09-04 |
| Redis fan-out, sequential against pipelined | 256 small publishes: 37.1 ms against 1.5 ms. 500 (the presence-target ceiling): 55.9 ms against 2.5 ms. `INCR` then `EXPIRE` as two round trips against one pipeline: 0.22 ms against 0.17 ms per request, which is why the rate limiter was left alone | `redis.asyncio` against the loopback instance on the developer machine | 2026-09-04 |
| The fan-out the bus actually issues, under its 1 MiB pipeline budget | A 50-member group at the 1024 bucket, 256 frames: 1 round trip, 2.6 ms, 0.9 MB of peak resident set. 500 presence frames: 1 round trip, 2.7 ms, 0.2 MB. The largest batch the body cap admits, 200 envelopes at the 262 144 bucket: 67 round trips, 129.2 ms — most of it `json.dumps` — and 11.1 MB. Unbounded, that last one held 178.3 MB against 37.8 MB for the same publishes issued one at a time, so the budget trades a round trip a frame down to a round trip a mebibyte without holding the fan-out twice | `realtime.bus.publish_many` against the loopback instance, `Pipeline.execute` counted and `ru_maxrss` read, on the developer machine | 2026-09-04 |
| One worker's resident set against its live socket count | 189.8 MB idle, 201.0 MB at 100 sockets, 214.4 MB at 250, 237.0 MB at 500 — 47 MB for the band's whole socket ceiling, about 94 kB each. It does not fall when the sockets close: the allocator keeps the pages | `ps -o rss=` against a real uvicorn on the developer machine, holding open `websockets` clients | 2026-09-04 |
| The concurrency limit against live sockets | With `--limit-concurrency 6`, six live WebSockets make every HTTP request answer uvicorn's own plain-text `503 Service Unavailable` — not this API's envelope. Both protocols share `server_state.connections`, the HTTP path sheds from the length of that shared set, and the WebSocket handshake never consults it, because the upgrade returns before the check. With the limit at 1024, 500 live sockets leave HTTP answering `200` | A real uvicorn on the developer machine, 6 then 500 `websockets` clients held open across an HTTP request | 2026-09-04 |
| Connection pool under contention | 60 concurrent drains through a pool of `max_size` 1 with a 1 s acquisition timeout: 60 × `200`, no timeout. The pool is not the binding constraint at these service times | `curl` × 60 against a real uvicorn on the seeded copy, `DB_POOL_MAX_SIZE=1 DB_POOL_TIMEOUT=1` | 2026-09-04 |

### 4.1 The request rate of one worker

Closed-loop, one uvicorn worker with the production flags, real PostgreSQL 16 and
Redis 7 on loopback, throttle rates raised so the numbers are the routes rather
than the limiter, against the seeded copy below. **Measured on the developer
machine, which has more than one core**, so the generator and the ORM threads did
not contend with the event loop the way they will on the VPS: read the shape — a
knee, then a decline — rather than the absolute rate. Verified 2026-09-04.

| Route (queries) | c=1 | c=8 | c=32 | c=128 |
|---|---|---|---|---|
| `GET /health` (0) | 1894 rps, p50 0.51 ms, p95 0.66 | 1352 rps, p50 3.07, p95 3.93 | 956 rps, p50 24.3, p95 90.9 | 796 rps, p50 116, p95 444 |
| `GET /me/envelopes` (2, 137 kB body) | 358 rps, p50 2.69, p95 3.43 | 576 rps, p50 13.3, p95 18.5 | 577 rps, p50 53.5, p95 72.2 | 88 rps, p50 749, p95 4292 |
| `GET /users` (2) | 557 rps, p50 1.74, p95 2.10 | 1014 rps, p50 7.54, p95 12.1 | 360 rps, p50 61.3, p95 256 | 233 rps, p50 388, p95 1555 |
| `GET /me/devices` (4) | 409 rps, p50 2.42, p95 2.69 | 706 rps, p50 11.0, p95 14.6 | 366 rps, p50 55.5, p95 262 | 116 rps, p50 800, p95 2774 |

The knee is between 8 and 32 concurrent requests. Past it throughput falls and
p95 grows faster than concurrency, which is one event loop saturating. Every
response was `200`; nothing was shed and nothing reached its deadline.

### 4.2 Query plans

`EXPLAIN (ANALYZE, BUFFERS)` on a seeded copy of the band's shape: 50 accounts,
500 devices, 200 000 undelivered envelopes at the 1024 bucket (247 MB with its
indexes), 25 000 device-log records, 20 000 attachments, 50 000 admin audit rows.
Developer machine, PostgreSQL 16, verified 2026-09-04. A buffer is 8 kB.

| Query | Plan | Buffers | Time |
|---|---|---|---|
| The retention pass with nothing expired, as it ran before this run: a `MAX(seq)` aggregate over the whole expired set, with no index | `Parallel Seq Scan` over the whole table | 28 736 | 26.5 ms |
| The same aggregate, with the index | `Index Scan using ix_queue_queued_hour` | 2 | 0.012 ms |
| The retention probe with nothing expired, as the batched sweep runs it now | `Index Scan using ix_queue_queued_hour`, `Limit` | 2 | 0.027 ms |
| One retention batch of 1000 ids | `Index Scan using ix_queue_queued_hour`, `Limit` | 991 | 5.04 ms |
| Expired attachments (20 000 rows, 9746 matching) | `Seq Scan` — 5.9 MB table, no index warranted | 272 | 1.39 ms |
| Expired audit rows (50 000 rows, 27 445 matching) | `Seq Scan` — 5.5 MB table, no index warranted | 468 | 7.48 ms |
| The drain page of a 400-row mailbox | `Index Scan using uq_queue_device_seq`, `Limit` | 19 | 0.10 ms |
| The drain page of a 32 768-row mailbox | the same index scan | 19 | 0.09 ms |
| The mailbox ceiling aggregate, 400-row mailbox | `Bitmap Heap Scan` on `uq_queue_device_seq` | 64 | 0.58 ms |
| The mailbox ceiling aggregate, 10 000-row mailbox | the same bitmap heap scan | 1 520 | 1.16 ms |
| The mailbox ceiling aggregate at the 32 MiB ceiling | `Parallel Seq Scan` — one device now holds 16% of the table, so the index stops being selective | 33 196 | 17.9 ms |
| The locked liveness read of 20 send targets | `LockRows` over a `Sort` over a hash join | 63 | 0.61 ms |
| The device-log keyset page | `Index Scan using uq_devicelog_user_seq`, `Limit` | 11 | 0.16 ms |
| The device-log head probe | `Index Only Scan Backward`, 0 heap fetches | 3 | 0.10 ms |
| The attachment quota aggregate, 400 held | `Bitmap Heap Scan` on the uploader index | 269 | 0.90 ms |
| The attachment quota aggregate at the 2 GiB quota ceiling (32 400 held) | `Seq Scan` — the table is narrow, so the whole scan is 5.4 MB | 694 | 1.82 ms |

Two of these grow with a ceiling rather than with the band, and both are recorded
as accepted risks with their triggers in
[`../../ACCEPTED_RISKS.md`](../../ACCEPTED_RISKS.md): the mailbox ceiling
aggregate (AR-7) and the attachment quota aggregate (AR-8). Neither is indexed
today, because at the band's real depths both are already cheap and an index on
either is maintained on the hottest write path in the system.

No restore drill, no failover drill, and no deploy has been timed. Those rows stay
absent until a drill produces them. ADR 0015 places the operator runbook at
`backend/ops/RUNBOOK.md`, which phase 5 creates, and `django-release-readiness`
owns the drill itself.

## 5. Domain rules

| Rule | What imposes it | What breaks when the code ignores it | verified |
|---|---|---|---|
| The server holds no content-encryption key. Its only secrets are the TLS key, the JWT signing key, the LiveKit API secret, the Django secret key, and the TURN secret | The threat model in `backend/SECURITY.md`: an attacker with live root on the VPS reads everything the server holds | Every message ever sent becomes readable from one seizure | 2026-09-03 |
| The server verifies no cryptographic material. A length, bucket or version check is a malformed-input guard and never a security control | `backend/SECURITY.md`; the client half is `backend/CLIENT_CONTRACT.md` | A client skips its own verification because "the server checks it", and the server is the adversary | 2026-09-03 |
| Every stored ciphertext has an exact bucket length; an off-bucket payload is rejected with `400 bad_bucket` and no echo | `backend/core/buckets.py` and `backend/core/fields.py` | Ciphertext length leaks message length, and the padding buys nothing | 2026-09-03 |
| No plaintext, no content key, no sender column, no membership table, no recipient list, and no shared-blob link exists at rest | `backend/core/tests/test_seizure_guard.py` and `test_manifest.py` | The social graph survives a seizure even though the content does not | 2026-09-03 |
| No server-side message history exists. An envelope row dies on ack, and an undelivered envelope dies after `ENVELOPE_TTL_DAYS` | The threat model; `messaging.QueuedEnvelope` | The server becomes the archive the design exists to avoid | 2026-09-03 |
| Every mailbox holds at most `MAILBOX_MAX_BYTES` of undelivered bytes and every device-list log at most `MAX_DEVICELOG_RECORDS` records | `messaging.services.send` and `devices.services.append_log`, under the locks they already hold; `messaging/tests/test_send_fanout.py` and `devices/tests/test_device_log.py` | Any member can address any mailbox and grow their own log without bound, and the rows of a mailbox carry no sender: one member fills the disk and the operator cannot name them | 2026-09-04 |
| No identifier, blob, token, password, address or request path reaches a log line, and no access log exists | The per-app `test_log_silence.py` suites and `backend/ops/audit/log_silence.py` | The log becomes the social graph that the schema refuses to hold | 2026-09-03 |
| Volatile data never touches disk: presence, signals, room text, rate counters and lockout state | Redis runs with `save ""` and `appendonly no` | A seized disk yields the traffic pattern | 2026-09-03 |
| No runtime foreign dependency exists; the system runs through a total national internet shutdown | The operating environment | The platform stops working at the moment it is most needed | 2026-09-03 |
| The server keeps no group state, no roster, and no group key | [ADR 0001](decisions/0001-pairwise-double-ratchet-group-fan-out.md) | A seizure yields the membership of every group | 2026-09-03 |
| No token is stored. Revocation is `Device.token_generation` and `Device.refresh_generation`, two integers on the device row | [ADR 0006](decisions/0006-device-bound-tokens-on-pyjwt.md); `core/tests/test_manifest.py` fails on a `token`, `jti` or blacklist column | A token table is a per-device login record at rest, which is the login history a seizure would otherwise yield | 2026-09-04 |

## 6. The seam between the two runtimes

FastAPI runs beside Django in one process. These are the facts of that seam, each
one discovered from the repository rather than assumed.

| Fact | The value here | verified |
|---|---|---|
| Seam shape | Same-process mount. FastAPI is the root ASGI application for every scope; the Django ASGI application is the router's `default`, so it answers every path no FastAPI route claims. A websocket scope that no route claims is refused with a close rather than the JSON `not_found` envelope, which would need the websocket denial-response extension | 2026-09-04 (observed, `backend/config/asgi.py`, `backend/api/app.py`) |
| Database each runtime connects to | One: the `default` PostgreSQL database. There is no second database and no second connection string | 2026-09-04 (observed, `config/settings/base.py`) |
| DDL owner | Django. There is no second migration tool, and the FastAPI side declares no schema of its own | 2026-09-04 (observed, `*/migrations/`) |
| Writer of each table | The Django ORM, in every case. The FastAPI routes write through the same models, inside synchronous units of work, so the field defaults, the `auto_now` values and the signals all run | 2026-09-04 (observed, `accounts/services.py`, `vault/services.py`, `devices/services.py`, `messaging/services.py`, `attachments/services.py`, `voicerooms/services.py`) |
| Data access layer | The Django ORM only, through `api/orm.py`: one synchronous function for each unit of work, bracketed with `close_old_connections()` and run with `sync_to_async(thread_sensitive=True)` inside a per-request `ThreadSensitiveContext`. A websocket scope enters no such context, so the gateway's four units share the one process-wide thread-sensitive executor thread | 2026-09-04 (observed, `api/orm.py`, `api/middleware.py`, `realtime/auth.py`) |
| Credential at the seam | One HS256 bearer token, issued and verified only by `api/auth.py`. The FastAPI dependencies and the WebSocket gateway both call that module, so a token the HTTP surface revokes is dead on the socket, and the revocation reaches a live socket over the bus within the publish latency | 2026-09-04 (observed, `api/auth.py`, `realtime/auth.py`, `realtime/bus.py`; asserted by `accounts/tests/test_device_auth.py` and `realtime/tests/test_revoke_close.py`) |
| Broker | None. There is no task queue and no Celery application; the only scheduled work is the `prune` management command under a systemd timer | 2026-09-04 (observed) |
| Cache | One Redis instance, `REDIS_URL`. The rate limiter, the login lockout, the room presence sets and the gateway's fan-out bus all use it, and every one of them reads strings through the redis client: the Django cache framework is not on Redis, so no value read from the instance is ever deserialized ([0018](decisions/0018-redis-is-authenticated-and-never-deserialized.md)). `api/redis.py` holds one `redis.asyncio` client for each running event loop, and the limiter, presence and the bus share it, so one process draws one pool plus the one connection the subscription holds. The limiter keys its counters under `ratelimit:`, the lockout keys its counter and its flag under `lock:<surface>:` for each of the two password surfaces, presence keys its sets under `roomlive:`, and the bus publishes to `ws:dev:<device id>` and `ws:room:<room id>`, which are channels rather than keys and store nothing. There is one counter stack, and no scope is counted twice | 2026-09-04 (observed, `api/redis.py`, `api/ratelimit.py`, `voicerooms/presence.py`, `realtime/bus.py`) |
| Process set | One uvicorn master with `WEB_CONCURRENCY` workers, default 1. Each worker serves HTTP and WebSocket alike and opens one Redis subscription connection of its own, so the subscription count tracks the worker count | 2026-09-04 (configured, `backend/ops/systemd/chat.service`) |
| Connection budget | `max_size` 16 per worker, so 16 × `WEB_CONCURRENCY` plus one for the maintenance timer while it runs: 17 at the default, against PostgreSQL's own default `max_connections` of 100. The VPS value of `max_connections` is not measured. `--limit-concurrency 512` bounds **connections**, live WebSockets included, so it is sized for the device ceiling of the band rather than for HTTP concurrency — the two share one knob and uvicorn offers no second | 2026-09-04 (observed, `config/settings/base.py`, `backend/ops/systemd/chat.service`) |
| Threads | One per in-flight HTTP request that touches the ORM: `api/middleware.ThreadSensitive` opens a `ThreadSensitiveContext` for each request, and asgiref builds a `ThreadPoolExecutor(max_workers=1)` for each context. A WebSocket scope enters no context, so every socket's ORM work shares the one process-wide thread-sensitive executor thread | 2026-09-04 (observed, `api/middleware.py`, `asgiref.sync.SyncToAsync.__call__`) |
| Lifespan | uvicorn sends both messages. Nothing is built at startup all the same, because what the process holds is keyed by running event loop: the shared Redis client, the bus subscriber and its reader task are built on first use. The shutdown drains every live socket with `1012`, stops the subscriber, then closes the client, in that order | 2026-09-04 (observed, `api/app.py`, `realtime/bus.py`, `realtime/gateway.py`) |
