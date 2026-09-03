# Chat backend

The Django backend of a self-hosted, end-to-end encrypted chat platform: direct
messages, group chats, and standalone voice rooms. The server relays and stores opaque
ciphertext and public keys; all cryptography runs in the client. The server never
holds a private key, a content key, or a plaintext message, and its schema stores no
conversation graph — an envelope knows its recipient device and nothing else.

Python 3.12, Django 6.0, Django REST Framework, Channels 4 on Daphne. PostgreSQL and
Redis are the only backing services, and there is no outbound network dependency at
runtime.

## Protocol and transport

**REST.** All HTTP endpoints live under `/api/v1`, JSON in and JSON out (DRF with a
JSON-only renderer; multipart is accepted solely for attachment upload). Binary values
cross the API base64-encoded. Errors share one envelope: `{"code": "...", "detail": ...}`.

**Authentication.** Bearer JWTs (`djangorestframework-simplejwt`, HS256, a dedicated
`JWT_SIGNING_KEY`). Login with a known device id yields a short-lived access token and
a rotating refresh token; every refresh blacklists the token it replaces. Tokens are
device-scoped: a `full`-scope token is bound to one device and carries a `tgen`
(token-generation) claim that is checked against the device row on every request, so
revoking a device — which bumps the generation — kills all its outstanding tokens
immediately. Login without a device yields a narrow `register`-scope token whose only
power is registering a device at `POST /api/v1/me/devices`.

**WebSocket.** One gateway at `/ws` (Django Channels over ASGI/Daphne, Redis channel
layer). Native clients authenticate with an `Authorization: Bearer` header on the
handshake; browsers, which cannot set WebSocket headers, connect bare and must send an
in-band `{"type": "auth", "access": "..."}` frame within ten seconds. The consumer
handles `ack`, `signal`, `subscribe_presence`, `room_subscribe`, `room_leave`, and
`room_signal` frames from the client, and emits `envelope`, `signal`, `presence`,
`room_signal`, and `room_presence` frames to it. Frames are JSON text only, size- and
rate-limited; protocol violations close the socket with code 4008, failed
authentication with 4001, an unlisted Origin with 4403, and revocation with 4003.

**Durable queue versus volatile relay.** A sent message is fanned out into one padded
ciphertext row per recipient device, held until that device drains and acks it (or the
TTL prunes it). A group message is the same fan-out over every member device, each copy
under its own pairwise session; the server holds no group object, roster, or group key.
Everything else — presence, typing-style signals, ephemeral room text —
is relayed between live sockets through the channel layer and never touches the
database or disk. If no socket is listening, a volatile signal is dropped.

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
- Redis 7, on loopback (cache, channel layer, and live room membership; configured
  non-persistent).
- Daphne serving ASGI behind nginx; nginx terminates TLS and serves attachment bytes.
- No CDN, no push service, no telemetry, no external CA or API. Dependencies are
  pinned and hashed in `requirements/`; the operator builds the untracked `vendor/`
  wheel cache with `ops/vendor.sh` while online, and `ops/offline_install.sh`
  installs from it with no network.

## Repository layout

| Path | Owns |
|---|---|
| `accounts` | User model, register/login/refresh/logout, user directory, encrypted profile blobs, device-aware JWT authentication |
| `devices` | Device registry, cross-signing identity, classical + ML-KEM prekeys, device-list log, peer bundles and claims, revocation cascade |
| `vault` | Recovery key backup (cross-signing private key material, opaque to the server) |
| `messaging` | Durable envelope queue: fan-out send, per-device drain, ack |
| `attachments` | Bucketed encrypted blob store with capability-id access |
| `voicerooms` | Persistent room records, LiveKit join tokens, live participant counts |
| `realtime` | The `/ws` gateway consumer and its socket-side auth |
| `core` | Size buckets, opaque blob field, env helpers, log scrubbing, health endpoint, deploy checks |
| `config` | Settings (`base`/`dev`/`prod`), ASGI entry point, root URLconf |
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
pytest
python manage.py check --deploy
```

Tests use `config.settings.dev` (see `pytest.ini`) and require both services running.
The dev settings fall back to insecure dev keys for `DJANGO_SECRET_KEY` and
`JWT_SIGNING_KEY` when unset; everything else reads from the environment.

## Configuration

Every environment variable the code reads, with its default:

| Variable | Default | Description |
|---|---|---|
| `DJANGO_SECRET_KEY` | — (required) | Django secret key |
| `DJANGO_ALLOWED_HOSTS` | empty | Comma-separated `ALLOWED_HOSTS` |
| `ADMIN_PATH` | `admin/` | URL path of the Django admin |
| `POSTGRES_DB` | — (required) | Database name |
| `POSTGRES_USER` | — (required) | Database role |
| `POSTGRES_PASSWORD` | — (required) | Database password |
| `POSTGRES_HOST` | `127.0.0.1` | Database host |
| `POSTGRES_PORT` | `5432` | Database port |
| `DB_CONN_MAX_AGE` | `60` | Persistent DB connection lifetime, seconds |
| `REDIS_URL` | `redis://127.0.0.1:6379/0` | Redis URL for cache, channel layer, and room presence |
| `JWT_SIGNING_KEY` | — (required) | HS256 signing key for all JWTs |
| `ACCESS_MIN` | `15` | Access-token lifetime, minutes |
| `REFRESH_DAYS` | `14` | Refresh-token lifetime, days |
| `REGISTER_SCOPE_ACCESS_MIN` | `10` | Register-scope token lifetime, minutes |
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
| `ALLOWED_WS_ORIGINS` | empty (dev: `http://localhost`) | WebSocket Origin allowlist; empty is a deploy-blocking error in prod |
| `WS_MAX_FRAME` | `524288` | Maximum WebSocket frame, bytes |
| `SIGNAL_MAX` | `16384` | Maximum volatile-signal blob, characters |
| `LIVEKIT_URL` | empty | Client-facing LiveKit URL; voice is 503 when unset |
| `LIVEKIT_API_KEY` | empty | LiveKit API key |
| `LIVEKIT_API_SECRET` | empty | LiveKit API secret (infrastructure secret, not a media key) |
| `LIVEKIT_TOKEN_TTL_SECONDS` | `300` | LiveKit join-token lifetime, seconds |

`.env.example` lists all of these plus `DJANGO_SETTINGS_MODULE` and the two coturn
values (`TURN_REALM`, `TURN_STATIC_AUTH_SECRET`) consumed by `ops/coturn/turnserver.conf`.

## Deployment

Deployment artefacts live under `ops/`: systemd units for Daphne and the maintenance
timer, the nginx site, coturn and LiveKit configuration, PostgreSQL setup notes, and
the offline-install scripts (`ops/vendor.sh`, `ops/offline_install.sh`). The operator
runbook in those directories is the authoritative sequence; this README does not
duplicate it.

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
