# Chat backend

The Django backend of a self-hosted, end-to-end encrypted chat platform: direct
messages, group chats, and standalone voice rooms. The server relays and stores opaque
ciphertext and public keys; all cryptography runs in the client. The server never
holds a private key, a content key, or a plaintext message, and its schema stores no
conversation graph — an envelope knows its recipient device and nothing else.

Python 3.12, Django 6.0, FastAPI on uvicorn. PostgreSQL and Redis are the only
backing services, and there is no outbound network dependency at runtime.

FastAPI is the only API surface. It is the root application and serves every route
of every app, `/ws` included; the Django application behind it answers `ADMIN_PATH`
and, in development, the static files the admin renders with. Any other path is this
API's own `404`, never a Django page. Django keeps the ORM, the migrations, the admin
panel and the settings.

`openapi.json` is the generated contract of that surface: `python manage.py openapi`
writes it and `--check` fails when the committed file is not what the routes produce,
which CI runs as its own job. Under `DEBUG` the same document is served at
`/openapi.json` with the interactive views at `/docs` and `/redoc`; all three are
closed otherwise, because a route map is reconnaissance on a server whose posture is to
reveal nothing, and the two interactive views load their JavaScript from a public CDN,
so the committed file is the reference that works offline.

## Protocol and transport

**REST.** All HTTP endpoints live under `/api/v1`, JSON in and JSON out. The one
exception is `POST /api/v1/attachments`, which takes a multipart body of exactly one
file part named `blob` and nothing else; its cap is the largest attachment bucket
plus `MULTIPART_OVERHEAD_BYTES`, and the bytes stream to disk one chunk at a time so
the process never holds a whole attachment. Binary values otherwise cross the API
base64-encoded. Errors share one envelope: `{"code": "...", "detail": ...}`, where
`detail` is a string except for `invalid_request`, which maps a field path to its
messages. No error body echoes request input. A request that fails validation is
`400 invalid_request`, a body above the route's cap is `413 payload_too_large`, and a
request past its deadline is `503 unavailable`.

**Authentication.** Bearer JWTs (PyJWT, HS256, a dedicated `JWT_SIGNING_KEY`). No
token is ever stored: a token table would be a per-device login record at rest, so
revocation lives in two counters on the device row instead. Login with a known device
id yields a short-lived access token and a rotating refresh token. Tokens are
device-scoped: a `full`-scope token is bound to one device and carries a `tgen`
(token-generation) claim checked against the device row on every request, so revoking a
device — which bumps the generation — kills all its outstanding tokens immediately. A
refresh token also carries `rgen`; a rotation advances `refresh_generation`, and a
refresh that presents an older value is a replay, which advances `token_generation` and
ends the whole family. Logout does the same for the calling device. Login without a
device yields a narrow `register`-scope token whose only power is registering a device
at `POST /api/v1/me/devices`. Both runtimes verify through the same module, so a token
one revokes is dead on the other.

**WebSocket.** One gateway at `/ws`, a Starlette WebSocket route of the same FastAPI
application. Native clients authenticate with an `Authorization: Bearer` header on the
handshake; browsers, which cannot set WebSocket headers, connect bare and must send an
in-band `{"type": "auth", "access": "..."}` frame within ten seconds. The gateway
handles `ack`, `signal`, `subscribe_presence`, `room_subscribe`, `room_leave`, and
`room_signal` frames from the client, and emits `envelope`, `signal`, `presence`,
`room_signal`, and `room_presence` frames to it. Frames are JSON text only, size- and
rate-limited; protocol violations and a slow consumer close the socket with code 4008,
failed authentication after the accept with 4001, revocation with 4003, and a shutdown
with 1012. A refusal decided before the accept — an unlisted Origin, or a bad header
token — ends the handshake instead, which the client sees as an HTTP failure.

**The fan-out bus.** A frame that has to reach a socket other than the one that sent it
goes through `realtime/bus.py`: Redis publish and subscribe over the async client, one
subscription connection for each worker process, with a topic per device
(`ws:dev:<device id>`) and per room (`ws:room:<room id>`). The gateway subscribes to a
topic on bind or on a room join and unsubscribes on the way out, so Redis drops a
publish nobody holds rather than carrying it to a worker that would discard it. Every
publisher — the send push, the revocation and deactivation closes, presence, and both
relays — publishes after its transaction has committed, and a publish that fails never
fails the request that caused it.

**Durable queue versus volatile relay.** A sent message is fanned out into one padded
ciphertext row per recipient device, held until that device drains and acks it (or the
TTL prunes it). A group message is the same fan-out over every member device, each copy
under its own pairwise session; the server holds no group object, roster, or group key.
Everything else — presence, typing-style signals, ephemeral room text —
is relayed between live sockets over the fan-out bus and never touches the database or
disk. If no socket is listening, a volatile signal is dropped.

**Voice.** Standalone voice rooms use a self-hosted LiveKit SFU, reverse-proxied at
`/rtc`. The backend mints short-lived LiveKit join tokens server-side
(`POST /api/v1/rooms/{id}/token`): audio-only grants scoped to one room and one
device, signed with the LiveKit API secret. Each sender's media key is generated
client-side and distributed to the other participants over pairwise sessions; no key
reaches the server or the SFU. A self-hosted coturn instance provides the TURN relay.

**Attachments.** Uploads are opaque encrypted blobs in fixed size buckets, stored on
disk under a 43-character unguessable capability id. Download responses carry an
`X-Accel-Redirect` header; nginx streams the bytes from an `internal` location, so
Django never serves file contents.

**Padding buckets.** Every stored ciphertext — envelopes, profiles, device labels,
room names, key backups, device-log records, attachments — must be
exactly one of a fixed set of sizes for its type. Off-bucket payloads are rejected
(`400 {"code": "bad_bucket"}`) without being echoed. Size-within-a-bucket is therefore
the only content-derived signal the server can observe.

**No server-side history.** The server stores message ciphertext only in the delivery
queue: rows are deleted when the recipient device acks them, and undelivered rows are
pruned after 7 days. History sync between a user's devices is client-to-client over the
ordinary envelope endpoint — a new device has no history until an existing device is
online to transfer it. There is no server history API.

## Runtime dependencies

- PostgreSQL 16, on loopback.
- Redis 7, on loopback (cache, rate counters, the gateway's fan-out bus, and live room
  membership; configured non-persistent).
- uvicorn serving ASGI behind nginx, supervised by systemd, with uvloop, httptools and
  the `websockets` sans-io implementation; nginx terminates TLS and serves attachment
  bytes. `WEB_CONCURRENCY` sets the worker count and defaults to 1; each worker opens
  one Redis subscription connection of its own. Everything loop-bound — the shared
  Redis client, the bus subscriber and its reader task — is built on first use and
  released on the lifespan shutdown, which also drains every live socket with 1012.
- No CDN, no push service, no telemetry, no external CA or API. Dependencies are
  pinned and hashed in `requirements/`; the operator builds the untracked `vendor/`
  wheel cache with `ops/vendor.sh` while online, and `ops/offline_install.sh`
  installs from it with no network.

## Repository layout

| Path | Owns |
|---|---|
| `api` | The FastAPI runtime and the seam: the composed application, token issue and verification, the error envelope, the shared Redis client and the rate limiter over it, the ORM unit-of-work helper, the pure-ASGI request limits |
| `accounts` | User model, register/login/refresh/logout, user directory, encrypted profile blobs |
| `devices` | Device registry, cross-signing identity, classical + ML-KEM prekeys, device-list log, peer bundles and claims, revocation cascade |
| `vault` | Recovery key backup (cross-signing private key material, opaque to the server) |
| `messaging` | Durable envelope queue: fan-out send, per-device drain, ack |
| `attachments` | Bucketed encrypted blob store with capability-id access |
| `voicerooms` | Persistent room records, LiveKit join tokens, live participant counts |
| `realtime` | The `/ws` gateway, the Redis publish-and-subscribe bus behind it, and its socket-side auth |
| `core` | Size buckets, opaque blob field, env helpers, log scrubbing, health endpoint, deploy checks |
| `config` | Settings (`base`/`dev`/`prod`), the ASGI entry point, root URLconf |
| `openapi.json` | The generated OpenAPI document of the whole surface, committed so a contract change is a diff in review. `manage.py openapi` writes it; `--check` gates it |
| `ops` | Deployment units, nginx/coturn/LiveKit/redis config, offline-install and audit tooling |
| `requirements` | Pinned, hashed dependencies. `vendor/` holds the offline wheel cache that `ops/vendor.sh` builds; it is not tracked in git |

## Local development

Install PostgreSQL 16 and Redis 7 natively (one-time database/user setup is described
in `ops/postgres/README.md`; start Redis with
`redis-server ops/redis/redis-chatapp.conf --daemonize yes`). Then:

```sh
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements/dev.txt
cp .env.example .env        # fill in dev values
set -a; source .env; set +a
python manage.py migrate
pytest
python manage.py openapi --check
python manage.py check --deploy
```

Tests use `config.settings.dev` (see `pytest.ini`) and require both services running.
The dev settings fall back to insecure dev keys for `DJANGO_SECRET_KEY` and
`JWT_SIGNING_KEY` when unset; everything else reads from the environment.

Each app holds exactly one `0001_initial` migration. A developer database that
recorded the history before it was regenerated cannot be migrated onto this one — drop
and recreate it, as `ops/postgres/README.md` describes. A route change that alters the
contract needs `python manage.py openapi` and the regenerated file committed with it.

## Configuration

Every environment variable the code reads, with its default:

| Variable | Default | Description |
|---|---|---|
| `DJANGO_SECRET_KEY` | — (required) | Django secret key |
| `DJANGO_ALLOWED_HOSTS` | empty | Comma-separated `ALLOWED_HOSTS` |
| `ADMIN_PATH` | `admin/` | URL path of the admin panel; the nginx site needs a matching location |
| `ADMIN_AUDIT_RETENTION_DAYS` | `90` | How long an admin audit row survives before `manage.py prune` deletes it |
| `POSTGRES_DB` | — (required) | Database name |
| `POSTGRES_USER` | — (required) | Database role |
| `POSTGRES_PASSWORD` | — (required) | Database password |
| `POSTGRES_HOST` | `127.0.0.1` | Database host |
| `POSTGRES_PORT` | `5432` | Database port |
| `DB_CONN_MAX_AGE` | `0` | Persistent DB connection lifetime, seconds. Must stay 0: the pool refuses a higher value, and nothing in this process fires the request signals that would reap a persistent connection |
| `DB_POOL_MIN_SIZE` | `1` | psycopg connection pool, minimum size |
| `DB_POOL_MAX_SIZE` | `16` | psycopg connection pool, maximum size; the ceiling on what one process takes from `max_connections` |
| `DB_POOL_TIMEOUT` | `10` | Seconds to wait for a pooled connection |
| `REDIS_URL` | `redis://127.0.0.1:6379/0` | Redis URL for the rate counters, the login lockout, the gateway bus, and room presence. Production carries the `requirepass` value as `redis://:<password>@127.0.0.1:6379/0`; `check --deploy` refuses a URL without one (`core.E004`) |
| `JWT_SIGNING_KEY` | — (required) | HS256 signing key for all JWTs |
| `ACCESS_MIN` | `15` | Access-token lifetime, minutes |
| `REFRESH_DAYS` | `14` | Refresh-token lifetime, days |
| `REGISTER_SCOPE_ACCESS_MIN` | `10` | Register-scope token lifetime, minutes |
| `REQUEST_DEADLINE_SECONDS` | `15` | Deadline for a request FastAPI serves; past it the answer is `503 unavailable` |
| `UPLOAD_DEADLINE_SECONDS` | `120` | Deadline for the attachment upload and the device/envelope batch routes |
| `BODY_CAP_JSON_BYTES` | `16384` | Body cap for a small-JSON route, and for any path no route claims |
| `BODY_CAP_BACKUP_BYTES` | `2097152` | Body cap for `PUT /api/v1/me/keybackup` |
| `BODY_CAP_BATCH_BYTES` | `73400320` | Body cap for the `devices` and `messaging` list bodies; matches nginx's `client_max_body_size 70m` |
| `MULTIPART_OVERHEAD_BYTES` | `8192` | Added to the largest attachment bucket to give `POST /api/v1/attachments` its cap |
| `THROTTLE_REGISTER` | `10/hour` | Rate limit: account registration |
| `THROTTLE_LOGIN` | `20/hour` | Rate limit: login |
| `THROTTLE_REFRESH` | `120/hour` | Rate limit: token refresh |
| `THROTTLE_ACCOUNTS` | `120/min` | Rate limit: general account/device/room endpoints |
| `THROTTLE_CLAIM` | `120/min` | Rate limit: prekey-bundle claims |
| `THROTTLE_ENVELOPES` | `600/min` | Rate limit: send/drain/ack |
| `THROTTLE_ATTACHMENTS` | `60/min` | Rate limit: attachment upload/download |
| `THROTTLE_ROOMTOKEN` | `60/min` | Rate limit: LiveKit join-token minting |
| `ATTACHMENTS_ROOT` | `<repo>/media_root` | Directory for attachment bytes |
| `ATTACH_USER_QUOTA_BYTES` | `2147483648` | Per-user attachment quota (2 GiB) |
| `ATTACH_TTL_DAYS` | `30` | Attachment retention, days |
| `ENVELOPE_TTL_DAYS` | `7` | Undelivered-envelope retention, days (delivered rows are deleted on ack; pruning records the per-device `pruned_through` watermark) |
| `MAX_DEVICES_PER_USER` | `10` | Live-device cap per account |
| `WEB_CONCURRENCY` | `1` | uvicorn worker processes; each opens its own Redis subscription for the gateway bus |
| `ALLOWED_WS_ORIGINS` | empty (dev: `http://localhost`) | WebSocket Origin allowlist; empty is a deploy-blocking error in prod |
| `WS_MAX_FRAME` | `524288` | Maximum WebSocket frame, bytes |
| `SIGNAL_MAX` | `16384` | Maximum volatile-signal blob, characters |
| `LIVEKIT_URL` | empty | Client-facing LiveKit URL; voice is 503 when unset |
| `LIVEKIT_API_KEY` | empty | LiveKit API key |
| `LIVEKIT_API_SECRET` | empty | LiveKit API secret (infrastructure secret, not a media key) |
| `LIVEKIT_TOKEN_TTL_SECONDS` | `300` | LiveKit join-token lifetime, seconds |

`.env.example` lists all of these plus `DJANGO_SETTINGS_MODULE` and the two coturn
values (`TURN_REALM`, `TURN_STATIC_AUTH_SECRET`) consumed by `ops/coturn/turnserver.conf`.

## The admin panel

The back office runs on [django-unfold](https://unfoldadmin.com/) at `ADMIN_PATH`,
served by the same uvicorn process as the API. It registers five things and hides
everything else: accounts, devices, voice rooms, attachments, and a read-only audit
log. It renders no ciphertext, no key or signature bytes, no password hash and no
token — a device label and a room name are ciphertext, so neither is shown.

There is one role, the superuser owner; a staff account that is not the owner gets an
empty panel. Every administrative act writes an audit row, bulk actions included, and
`manage.py prune` deletes a row older than `ADMIN_AUDIT_RETENTION_DAYS`. Five failed
sign-ins lock an account name for fifteen minutes, in Redis and nowhere else, and a
session lasts at most eight hours and ends at browser close.

Every asset is served by this deployment: run `python manage.py collectstatic` on
deploy, and nginx serves `STATIC_ROOT` — without it the panel renders unstyled. The
nginx site needs a `location` for `ADMIN_PATH`; `ops/nginx/chat.nimashadloo.dev.conf`
carries the default one, and it and `ADMIN_PATH` are one setting in two places.

[`docs/admin/PANEL-RECORD.md`](../docs/admin/PANEL-RECORD.md) is the system of record
for the panel: the pinned release, every position with its band and flip signal, the
override ledger, the role model, the upgrade debts and the deferrals. Read it before
changing the panel.

## Deployment

Deployment artefacts live under `ops/`: systemd units for uvicorn and the maintenance
timer, the nginx site, coturn and LiveKit configuration, PostgreSQL setup notes, and
the offline-install scripts (`ops/vendor.sh`, `ops/offline_install.sh`). The operator
runbook in those directories is the authoritative sequence; this README does not
duplicate it. One step is worth naming because nothing fails loudly without it:
`python manage.py collectstatic --noinput` must run on every deploy that changes a
dependency, or nginx serves an empty `STATIC_ROOT` and the panel loads with no styling
at all.

## What the server can still see

End-to-end encryption bounds what this server stores, not what it can observe while
running. The operator can see which accounts exist, which devices connect and when,
connection metadata such as IP addresses, and the size bucket and timing of every
stored or relayed blob — and a live operator watching the routing can log which
connection writes to and reads from which device queue, i.e. who talks to whom and
when. The social graph is not hidden from a live, hostile operator; message content is.
The schema stores none of that graph at rest, so a seized disk yields only what
[SECURITY.md](SECURITY.md) enumerates.

Further reading: [SECURITY.md](SECURITY.md) for the full threat model and residual
risk, [CLIENT_CONTRACT.md](CLIENT_CONTRACT.md) for the client-side halves of every
security property.
