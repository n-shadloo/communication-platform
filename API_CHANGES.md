# API changes

Everything a client can observe that has moved since the pre-rebuild state, for the
developer writing that client. One document, organised by the kind of change rather
than by the run that made it: the error vocabulary, then authentication, then the
routes and fields that left or changed, then realtime, then the surface that did not
move at all.

Every entry names the route or the field, the old behaviour, the new behaviour, and
what the client does about it. Nothing here repeats an endpoint reference — the
per-app [`backend/*/API.md`](backend/) files are the reference, and
[`backend/openapi.json`](backend/openapi.json) is the same contract in a form a
generator reads. This file records only what moved, and
[`backend/CLIENT_CONTRACT.md`](backend/CLIENT_CONTRACT.md) records what the client
must do for the security properties to hold.

Two things caused most of it. The HTTP surface left Django REST Framework for FastAPI
([ADR-0002](docs/architecture/decisions/0002-fastapi-as-the-only-http-api-surface.md))
and the `/ws` gateway left Channels for a WebSocket route of that same application
([ADR-0004](docs/architecture/decisions/0004-websocket-gateway-on-redis-pubsub.md)).
Groups left MLS for pairwise Double Ratchet fan-out
([ADR-0001](docs/architecture/decisions/0001-pairwise-double-ratchet-group-fan-out.md)),
which removed three routes and a request field.

## The error vocabulary

Every error of every route is now one envelope:

```json
{ "code": "…", "detail": "…" }
```

`detail` is a string on every code but `invalid_request`, where it maps a field path
to the list of messages that failed. **No error body echoes request input**, and a
`500` carries no traceback and no detail beyond a fixed string. Branch on `code`,
never on `detail`. The complete table of codes is in
[`backend/core/API.md`](backend/core/API.md).

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| A validation failure | The bare Django REST Framework field-error object, with no `code` key: `{"ik_pub": ["invalid base64"]}`, and a nested item as `{"otpks": {"0": {"pub": [...]}}}` | `400 {"code": "invalid_request", "detail": {"ik_pub": ["invalid base64"]}}`, and a nested item as a dotted path: `{"otpks.0.pub": ["invalid base64"]}` | Parse the envelope, and read the field path as a dotted string rather than walking a nested object |
| Validation messages | REST Framework's text, for example `"This field is required."` | Pydantic's text, for example `"Field required"`. The length and base64 guards keep their own wording — `"invalid base64"`, `"bad key length"`, `"bad signature length"`, `"duplicate key_id"` | Show `detail` values; never match on their text |
| The status of a validation failure | `400` | `400`, unchanged. FastAPI's own default is `422` with a nested error list; this surface never returns `422`, and the published schema does not describe one | None. A client generated from the schema will not see a `422` branch |
| `bad_request` | `400 {"code": "bad_request", ...}` on a malformed upload body and a malformed ack body | Retired. Both are `400 {"code": "invalid_request", "detail": {...}}` | Replace the `bad_request` branch with `invalid_request` |
| A rate-limited request | `429 {"detail": "Request was throttled."}` | `429 {"code": "throttled", "detail": "Request was throttled."}`, with a `Retry-After` header in seconds | Read `Retry-After` and back off |
| A wrong method | `405 {"detail": "Method \"DELETE\" not allowed."}`, with `Allow` naming every method the route serves | `405 {"code": "method_not_allowed", "detail": "That method is not allowed."}`. `Allow` names the methods of one route object, so on a path two methods share it names one of them and not both | Branch on `code`. Never read `Allow` as the complete method set of a path |
| A path no route serves | Django's own `404` page, in `text/html` | `404 {"code": "not_found", "detail": "No such route or resource."}`, with the security headers every other response carries | Branch on `code`. A typo'd path and a missing resource are no longer told apart by content type |
| An unhandled failure | Django's `500` page | `500 {"code": "server_error", "detail": "Internal error."}` | None |

Four refusals are new, because the limits behind them are new.

| Code | Status | When | Client action |
|---|---|---|---|
| `payload_too_large` | `413` | The body is above the route's cap, counted as the bytes arrive rather than read from `Content-Length` | Each route's reference names its cap. Do not trust an understated `Content-Length` to get a body through |
| `unavailable` | `503` | The request outlived its deadline, or a throttled route's counter store is unreachable | Treat `503` as an outage and `429` as backoff. They are not the same signal |
| `invalid_request` on the `Host` header | `400` | The `Host` header is not one the server lists: `{"host": ["Unknown host."]}` | Send the deployment's own hostname |

`payload_too_large` now shares `413` with `quota_exceeded`, which is unchanged and
means the account's attachment quota is exhausted. Branch on `code`, not on the
status.

Every response now carries `X-Content-Type-Options: nosniff`, `Cache-Control:
no-store` and `Referrer-Policy: no-referrer`.

## Authentication

There is **no token table and no blacklist**. Revocation is two integers on the device
row, `token_generation` and `refresh_generation`
([ADR-0006](docs/architecture/decisions/0006-device-bound-tokens-on-pyjwt.md)). A
stored token is a per-device login record at rest, which is exactly what the schema
refuses to hold.

### The `401` bodies

| Condition | Old body | New body | Client action |
|---|---|---|---|
| No `Authorization` header, or one that is not `Bearer <token>` | `401 {"detail": "Authentication credentials were not provided."}` | `401 {"code": "unauthenticated", "detail": "Authentication credentials were not provided."}`, with `WWW-Authenticate: Bearer` | Branch on `code` |
| A malformed, expired, or wrong-type token | `401 {"detail": "Given token not valid for any token type", "code": "token_not_valid", "messages": [...]}` | `401 {"code": "invalid_token", "detail": "Token is missing, malformed, or expired."}`. The `messages` array is gone | Replace the `token_not_valid` branch with `invalid_token`; drop any use of `messages` |
| A revoked device, a stale generation, or a deactivated account | `401 {"code": "token_revoked"}` | `401 {"code": "token_revoked", "detail": "Token is no longer valid."}` | None beyond comparing `code` |

### Logout, refresh, and login

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `POST /api/v1/auth/logout` | Required `{"refresh": "..."}`, blacklisted that one token, and answered `205 Reset Content`. The access token stayed valid until it expired | Takes **no body**, and answers `204 No Content`. It advances the device's `token_generation`, so the presented access token **and every refresh token of that device** die immediately, and the device's sockets close | Send no body. Treat `204` as success and discard both tokens. A retry with the same access token answers `401 token_revoked`, which is also success |
| Replaying a refresh token that was already rotated | `401`; the replayed token was blacklisted and the newest pair kept working | `401 {"code": "token_revoked", ...}`, **and the whole family dies**: `token_generation` advances, the newest access and refresh tokens die with it, and the device's sockets close | **Never retry a refresh with the same token**, including after a timeout or a network error. On an unclear outcome, log in again |
| A successful refresh | Returned a new pair; the old refresh was blacklisted | Returns a new pair; the old refresh is behind the generation and is now a replay | Replace the stored refresh token on every call, before any retry |
| A register-scope token presented to `/api/v1/auth/refresh` | `401 {"code": "token_revoked"}` | `401 {"code": "invalid_token", ...}`, refused before any database read | Branch on `invalid_token` as well |
| `POST /api/v1/auth/login` with a `device_id` | Left outstanding refresh tokens alone | Advances that device's `refresh_generation`, so a refresh token the device still held becomes a replay | Discard the previous session's tokens when a login returns a new pair |
| `device_scope_required` | Documented on the mailbox routes and the join-token route, and unreachable on all of them: a full-scope token always names a device | Returned by no route. It stays in the vocabulary and nothing answers it | Delete the branch |

`POST /api/v1/me/devices` is the one route a register-scope token reaches. Every other
authenticated route answers `403 {"code": "scope_forbidden", ...}` to one.

## Removed routes

Each path below is gone. The response is now the JSON envelope, not Django's `404`
page — an unmatched path under `/api/v1` is `404 {"code": "not_found", "detail": "No
such route or resource."}`.

| Route | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `PUT /api/v1/me/devices/{device_id}/keypackages` | Stored up to 100 consumable MLS key packages per device, plus one last-resort package, and returned `{"keypackage_count": n}`; `409 {"code": "keypackage_limit"}` at the cap | `404 not_found` | Delete the upload path. Nothing replaces it: a group start needs no key package |
| `GET /api/v1/me/devices/{device_id}/keypackages/count` | Returned `{"keypackage_count": n}` for the calling device's consumable pool | `404 not_found` | Delete the poll. Poll one-time prekeys instead, on `GET /api/v1/me/devices/{device_id}/prekeys/count` (`otpk_count`, `pq_otpk_count`) |
| `POST /api/v1/users/{user_id}/keypackages/claim` | Returned one MLS key package per live device of the user as `{"keypackages": [{"device_id": …, "blob": …}]}`, consuming it, or the device's last-resort package when its pool was empty | `404 not_found` | Start a group session by claiming PQXDH bundles from `POST /api/v1/users/{user_id}/keys/claim` for each member, exactly as for a direct message (`backend/CLIENT_CONTRACT.md` §F) |

**The server has no counterpart for an MLS profile.** No endpoint accepts, stores or
serves a key package, a Welcome, a commit, or any other MLS artefact, and none will.
`KEYPACKAGE_BUCKETS` is gone from `backend/core/buckets.py`, so no blob type pads to
`[4096, 16384]` any more; delete the constant and the padding code that used it.
`KEYPACKAGE_TTL_DAYS` is gone from the server environment, which is the operator's
concern and not the client's.

## Changed request fields

| Field | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `keypackages` in `POST /api/v1/me/devices` | A required list, empty or up to 100 base64 blobs each padded to a key-package bucket | Refused like any other unknown field, an empty list included | Remove the field from the registration body |
| `refresh` in `POST /api/v1/auth/logout` | Required | The route takes no body at all; one sent is ignored | Send no body |
| A JSON value of the wrong type, anywhere | Coerced where possible: `"1"` and `true` both arrived as the integer `1` | `400 invalid_request`. A string is a string, an integer is an integer, and a boolean is a boolean | Send the declared JSON types |
| An unknown field, anywhere | Rejected, with the bare field-error object: `{"junk": "Unexpected field."}` | Rejected, with the envelope: `{"junk": ["Extra inputs are not permitted"]}` | Send only the declared fields |
| `{"device_ids": null}` in `POST /api/v1/users/{user_id}/keys/claim` | `400`; the field rejected an explicit null | Accepted, and it means what omitting the field means: every live device of that user. An explicit `[]` still claims nothing | Omit a field you do not want to send rather than sending null. `{"ids": null}` on ack is still a `400` |
| A multipart body on `POST /api/v1/attachments` with a second part beside `blob` | Accepted and ignored | `400 invalid_request` | Send exactly one part, named `blob` |

## Changed status codes

| Outcome | Old status | New status | Client action |
|---|---|---|---|
| `POST /api/v1/auth/register` with a name that exists | `400 {"code": "username_taken"}` | `409 {"code": "username_taken"}`. The concurrent race answers `409` too | Move the branch from `400` to `409` |
| `POST /api/v1/auth/logout` | `205 Reset Content` | `204 No Content` | Treat `204` as success |
| A malformed `{user_id}`, `{device_id}` or `{room_id}` in a path | `404`, from the URL resolver | `400 {"code": "invalid_request", "detail": {"user_id": [...]}}` | Treat a malformed id as a client bug, not a missing resource |
| A request that outlives its deadline | Held until the client gave up | `503 {"code": "unavailable", ...}` | Retry with backoff, honouring the retry semantics of the route |
| A throttled route while the counter store is unreachable | An unhandled `500` | `503 {"code": "unavailable", ...}` | Treat as an outage |
| A body above the route's cap | Reached the route, or was refused by nginx with an HTML page | `413 {"code": "payload_too_large", ...}` from the application, on every route | Each route's reference names its cap |
| A body between 64 MiB + 8 KiB and 70 MiB on `POST /api/v1/attachments` | Reached the route and was refused as off-bucket | `413 payload_too_large`, because the upload now carries a cap of its own: the largest attachment bucket plus the multipart wrapper | None, for a client that pads to a bucket |

## Changed response fields

No success body changed. Every change below is in an error body.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| The `detail` of a validation failure | A nested object mirroring the body's shape | A flat map of dotted field paths to messages, so a list item carries its index in the path | Read the path as a string |
| `messages` in a token refusal | An array of per-check messages | Gone | Drop any use of it |
| `stale_version`, `not_found`, `token_revoked`, `voice_unconfigured` | The code with no `detail`, or with none on some routes | Every one carries a `detail` string | Compare `code`, never the whole body |
| An unknown room on `PUT /api/v1/rooms/{room_id}` | `404` with an empty body | `404 {"code": "not_found", "detail": "No such room."}` | Parse the refusal as JSON |
| `pruned_through` in `GET /api/v1/me/envelopes` | The same integer, but a lost envelope may have been an MLS commit: the device was permanently desynced from those groups and had to be removed and re-added with a fresh Welcome | The same integer — the highest `seq` the TTL prune has deleted from this mailbox, 0 if never. A lost envelope may now have carried a Double Ratchet message or a group control event | Replace the remove-and-re-add flow with the repair flow (`backend/CLIENT_CONTRACT.md` §H) |

## Realtime

The `/ws` gateway is a WebSocket route of the same FastAPI application, with Redis
publish and subscribe behind it. **The frame protocol did not change.** Every client
frame (`auth`, `ack`, `signal`, `subscribe_presence`, `room_subscribe`, `room_leave`,
`room_signal`), every server frame (`envelope`, `signal`, `presence`, `room_signal`,
`room_presence`), their exact shapes, the URL, the two handshake paths, the
ten-second authentication deadline, the Origin policy, and every limit in
[`backend/realtime/API.md`](backend/realtime/API.md) are as they were.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| An unlisted `Origin` header | Documented as close **4403**. The code never in fact reached the client, because the refusal was decided before the accept | The server answers the upgrade request `403 Forbidden` and no socket is established. 4403 remains the name of the refusal in the reference | Treat a failed handshake as a refusal |
| A bad `Authorization: Bearer` token on the handshake | Documented as close **4001** "immediately after accept" | The same `403 Forbidden` failed handshake. 4001 still arrives on the browser path, where the socket is accepted first and the token comes in an `auth` frame | On the header path, read a failed handshake as "refresh the access token and reconnect". A handler waiting for 4001 there will never fire |
| A server restart | The socket dropped with no code | Close **1012**, after every live socket is drained | Reconnect after a backoff. This is a deploy, not a fault, and must not count toward a failure budget that disables reconnection |
| A socket that is not reading | Unbounded in practice; the process's memory grew | At most 256 undelivered server frames, then close **4008** — the same code as a protocol violation | Read continuously. A 4008 with no preceding protocol error means the client fell behind: reconnect and drain the durable queue over REST |

**Delivery, stated plainly.** A live frame is dropped if no socket holds the topic at
the instant it is published, which includes the window while a device is
reconnecting. This was always true and the durable queue was always the contract;
publish and subscribe makes it structural rather than incidental. Nothing about
`envelope` delivery changed: the row stays in the mailbox until it is acked, so a
missed push costs a poll and never a message.

## The unchanged surface, route by route

Every route below keeps its path, its method, its success status, its success body,
its headers and its limits. Only the error bodies moved, in the ways above. The
reference for each is its app's `API.md`; the machine-readable form of all of them is
[`backend/openapi.json`](backend/openapi.json).

| Method | Path | Success | Reference |
|---|---|---|---|
| `GET` | `/api/v1/health` | `200` | [core](backend/core/API.md) |
| `POST` | `/api/v1/auth/register` | `201` | [accounts](backend/accounts/API.md) |
| `POST` | `/api/v1/auth/login` | `200` | [accounts](backend/accounts/API.md) |
| `POST` | `/api/v1/auth/refresh` | `200` | [accounts](backend/accounts/API.md) |
| `POST` | `/api/v1/auth/logout` | `204` | [accounts](backend/accounts/API.md) |
| `GET` | `/api/v1/users` | `200` | [accounts](backend/accounts/API.md) |
| `GET` | `/api/v1/users/{user_id}/profile` | `200` | [accounts](backend/accounts/API.md) |
| `GET` | `/api/v1/me/profile` | `200` | [accounts](backend/accounts/API.md) |
| `PUT` | `/api/v1/me/profile` | `200`, empty body | [accounts](backend/accounts/API.md) |
| `GET` | `/api/v1/me/keybackup` | `200` | [vault](backend/vault/API.md) |
| `PUT` | `/api/v1/me/keybackup` | `200`, empty body | [vault](backend/vault/API.md) |
| `PUT` | `/api/v1/me/identity` | `200`, empty body | [devices](backend/devices/API.md) |
| `GET` | `/api/v1/users/{user_id}/identity` | `200` | [devices](backend/devices/API.md) |
| `POST` | `/api/v1/me/devices` | `201` | [devices](backend/devices/API.md) |
| `GET` | `/api/v1/me/devices` | `200`, or `304` against `If-None-Match` | [devices](backend/devices/API.md) |
| `PUT` | `/api/v1/me/devices/{device_id}` | `200`, empty body | [devices](backend/devices/API.md) |
| `DELETE` | `/api/v1/me/devices/{device_id}` | `204` | [devices](backend/devices/API.md) |
| `PUT` | `/api/v1/me/devices/{device_id}/prekeys` | `200` | [devices](backend/devices/API.md) |
| `GET` | `/api/v1/me/devices/{device_id}/prekeys/count` | `200` | [devices](backend/devices/API.md) |
| `POST` | `/api/v1/me/devicelog` | `201` | [devices](backend/devices/API.md) |
| `GET` | `/api/v1/users/{user_id}/devicelog` | `200` | [devices](backend/devices/API.md) |
| `GET` | `/api/v1/users/{user_id}/devices` | `200`, or `304` against `If-None-Match` | [devices](backend/devices/API.md) |
| `POST` | `/api/v1/users/{user_id}/keys/claim` | `200` | [devices](backend/devices/API.md) |
| `POST` | `/api/v1/envelopes` | `202` | [messaging](backend/messaging/API.md) |
| `GET` | `/api/v1/me/envelopes` | `200` | [messaging](backend/messaging/API.md) |
| `POST` | `/api/v1/me/envelopes/ack` | `200` | [messaging](backend/messaging/API.md) |
| `POST` | `/api/v1/attachments` | `201` | [attachments](backend/attachments/API.md) |
| `GET` | `/api/v1/attachments/{attachment_id}` | `200`, the bytes | [attachments](backend/attachments/API.md) |
| `POST` | `/api/v1/rooms` | `201` | [voicerooms](backend/voicerooms/API.md) |
| `GET` | `/api/v1/rooms/{room_id}` | `200` | [voicerooms](backend/voicerooms/API.md) |
| `PUT` | `/api/v1/rooms/{room_id}` | `200`, empty body | [voicerooms](backend/voicerooms/API.md) |
| `POST` | `/api/v1/rooms/{room_id}/token` | `200` | [voicerooms](backend/voicerooms/API.md) |
| — | `/ws` | the accepted socket | [realtime](backend/realtime/API.md) |

A trailing-slash mismatch is a `404` and was a `404` before. It is named here because
FastAPI's own default is a `307` redirect: that is turned off, because the redirect
rebuilds an absolute address from the request path and drops any prefix a proxy
stripped, which turns a write into a lost request.

Also unchanged, and worth naming because a rewrite is where these usually break: the
`register` and `full` scope split and what each scope reaches; the timing-equalised
login and its `403 account_inactive`; both device-list `ETag`s, their `304` with an
empty body, and what each tag covers; `log_head_seq`, `has_more`, `head_seq`,
`pruned_through`, `etag`, `accepted` and `stale_devices` in the bodies that carry
them; the lenient clamping of `after` and `limit` on the device log and of `limit` on
the drain, which still never error; every list and pool cap — 256 items per send, 200
ack ids, a 100-envelope drain, 200 classical and 100 PQ prekeys per pool and per
payload, 100 claim ids, 50 device-log records, a 200-record log page — with the same
public-key, signature and base64 bounds; the registration refusal of `cross_sig` and
`bundle_version` and the message naming the endpoint that accepts them; the
first-device identity exemption and `400 identity_required` past it; the device cap
and its `409 device_limit`; `409 prekey_limit`, and the rule that a refused
replenishment rotates nothing; verbatim `cross_sig` with its nulls, and the omission
of every PQ member from a classical-only bundle; single consumption of a one-time
prekey under concurrent claims; the revocation cascade and the socket close behind
it; the padding buckets of every other blob type and `400 bad_bucket` with no echo of
the payload; the `409 stale_version` rule on both versioned blobs; and every throttle
scope name, its environment variable and its default.

## What the client can build against now

**The surface is frozen at `v1` from this merge.** It is published two ways and they
are the same contract:

- [`backend/openapi.json`](backend/openapi.json) — the OpenAPI document, generated
  from the routes. Every path, method, request shape, response shape and status is in
  it, including every error status each route can answer, each with the envelope. CI
  fails a change that does not regenerate it, so it cannot describe a server that no
  longer exists.
- The per-app `API.md` files — the same routes in prose, plus what a schema cannot
  carry: the retry semantics of every mutating route, the padding buckets, and the
  WebSocket close codes.

There is **no idempotency store**, because a stored response for a send would link a
sender to its recipients at rest — which is the one thing the schema is built to
avoid. Every mutating route documents what a retry of it does instead, and that text
is part of the contract. Read it before you write a retry policy.

The version stays `v1`. No released client exists, so no deprecation cycle is owed to
anyone; when one does, `v2` becomes a path rather than a note here
([ADR-0007](docs/architecture/decisions/0007-contract-conventions.md)).

**From here, every observable change gets a new section in this file, above this
one**, naming the route or field, the old behaviour, the new behaviour and the client
action. A change that reaches a client without a section here is a defect.
