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
| ASGI application | VPS, uvicorn on `127.0.0.1:8000`, systemd unit `chat.service` (writes `media_root` and nothing else), user `deploy`, `WEB_CONCURRENCY` workers (default 1), uvloop and httptools, the `websockets` sans-io implementation. In-process: FastAPI is the root application for every scope — every API route, the `/ws` gateway, and the Django ASGI application answering `ADMIN_PATH` alone | PostgreSQL and Redis on loopback | 2026-09-04 (configured, `backend/ops/systemd/chat.service`; composition observed in `backend/config/asgi.py`) |
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
| Pinned production distributions | 29, down from 42 when Channels, daphne and the sixteen packages only they pulled in left | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/prod.txt` | 2026-09-04 |
| Pinned development distributions | 13 | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/dev.txt` | 2026-09-04 |
| Project apps | 8 — `core`, `accounts`, `devices`, `vault`, `messaging`, `attachments`, `voicerooms`, `realtime` | `INSTALLED_APPS` | 2026-09-03 |
| Project models | 11 | `django.apps.apps.get_models()` filtered to the project apps | 2026-09-03 |
| Migration files | 6 — one `0001_initial` for each app that owns a table, per [0009](decisions/0009-regenerate-the-initial-migrations.md), down from 16 | `git ls-files 'backend/*/migrations/0*.py' \| wc -l`. Run over the working tree instead and `backend/.venv` adds 23 of Django's own | 2026-09-04 |
| Tracked Python files | 185 | `git ls-files '*.py' \| wc -l` | 2026-09-04 |
| Test files | 71 | `git ls-files '*/test_*.py' \| wc -l` | 2026-09-04 |
| Tests collected | 1172, plus 48 subtests. The rise over the previous run's 1102 is the phase-4 security audit: every fix landed with the test that failed before it, and the audit's own gates — the planted pickle, the deploy checks read through the registry, the ceilings, the scrubbed traceback | `pytest -q` | 2026-09-04 |
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
| Full test suite | 46.2 s, 1172 passed, 48 subtests | Developer machine, `pytest -q`, native PostgreSQL 16 and Redis 7 on loopback, random order (`pytest-randomly` seed reported per run) | 2026-09-04 |
| Full test suite, second order | 45.8 s, 1172 passed, 48 subtests | Same machine, a different `pytest-randomly` order in the same session. The spread between the two orders is the cost of the `transaction=True` tests, whose table truncation lands in a different place each run | 2026-09-04 |
| Gateway suite against a real Redis bus | 6.8 s, 56 passed | Developer machine, `pytest realtime/ -q -p no:randomly`. Every socket test drives the composed ASGI application on the test's own event loop and fans out through Redis publish and subscribe; three of them run a real uvicorn on an ephemeral port | 2026-09-04 |
| The regenerated migration history against the one it replaced | The same schema: 104 columns, 47 indexes and 61 constraints, identical name for name and definition for definition. The one difference is the physical column order of `devices_device`, where the four columns the old history appended now sit in model order | Both histories applied to a scratch database of their own on the developer machine, then `information_schema.columns`, `pg_indexes` and `pg_constraint` dumped from each and diffed. The `AddField` for `Device.refresh_generation` this row used to time is part of `devices.0001_initial` now and no longer runs against a populated table | 2026-09-04 |
| Every `0001_initial`, forward and back | Every statement is a `CREATE TABLE`, a `CREATE INDEX` or an `ALTER TABLE … ADD CONSTRAINT` against a relation the same migration created, so each ACCESS EXCLUSIVE lock is on a relation no other session can name. Every app reaches `zero` again, `accounts` cascading through `admin` on the way | `python manage.py sqlmigrate <app> 0001` read statement by statement, and `core/tests/test_migrations.py` for the replay | 2026-09-04 |
| Test-database teardown | warns on roughly one run in three: `database "test_chatapp" is being accessed by other users`, one session | Developer machine, `pytest -q` repeated. It is a teardown warning and never a failure; the suite is green either way, and CI is unaffected because each run builds a fresh database. Reproduced with `DB_POOL_MIN_SIZE=0`, so it is not the pool's idle connection but a connection a worker thread still holds when `destroy_test_db` runs | 2026-09-04 |
| Send fan-out | 4 queries of its own, at 1, 6 and 20 recipients alike, and 4 for ten envelopes to one mailbox: one locked liveness read, one aggregate of the undelivered bytes each target holds (the mailbox ceiling), one bulk counter update, one bulk insert. A batch that reaches only stale devices costs the liveness read alone. The authentication dependency adds one query to every route | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `messaging/tests/test_query_counts.py` | 2026-09-04 |
| Prekey claim | 1 target read, 1 locked select per target device, and 1 delete for the batch — 3 queries of its own for one device with a pool of 1, 20 or 200 keys, and 8 for six devices. An exhausted pool costs one less, because nothing is deleted | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `devices/tests/test_query_counts.py` | 2026-09-04 |
| Attachment upload | 3 queries of its own — the uploader's row lock, one `SUM` aggregate, one insert — at 0 and at 25 attachments already held. The download is 1. The authentication dependency adds one query to every route | `CaptureQueriesContext` over the composed application, transaction statements excluded, in `attachments/tests/test_query_counts.py` | 2026-09-04 |
| Offline install of the regenerated set | 54 hash-verified wheels collected and installed with `--no-index` | `pip download --require-hashes --only-binary=:all: -r requirements/dev.txt`, then `pip install --no-index --find-links` into a fresh venv, on the developer machine | 2026-09-04 |
| Hash-verified dependency install | 7 s to fetch and install the two added wheels | `pip install --require-hashes -r requirements/dev.txt` on the developer machine, online | 2026-09-03 |

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
| Lifespan | uvicorn sends both messages. Nothing is built at startup all the same, because what the process holds is keyed by running event loop: the shared Redis client, the bus subscriber and its reader task are built on first use. The shutdown drains every live socket with `1012`, stops the subscriber, then closes the client, in that order | 2026-09-04 (observed, `api/app.py`, `realtime/bus.py`, `realtime/gateway.py`) |
