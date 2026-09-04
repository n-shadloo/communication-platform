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

No success body changed **in the rebuild**. Every change in this section is in an error
body; the one success body that has moved since arrived later and is recorded under
[What the security audit bounded](#what-the-security-audit-bounded).

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

## The operator can now remove things the client could reach

The admin panel landed in phase 3
([ADR-0011](docs/architecture/decisions/0011-django-unfold-admin-panel.md)). It moved
no route, no field, no status code and no error code: `backend/openapi.json` is
byte-identical across the change, and no request a client makes behaves differently.

What did change is what an operator can do to state a client is holding a reference
to. Two of them are new, and a client that assumed permanence will see a `404` it
could not see before.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `GET /api/v1/rooms/{id}`, `PUT /api/v1/rooms/{id}`, `POST /api/v1/rooms/{id}/token` | A room, once created, existed forever. Nothing deleted one — no route, no retention sweep | The operator can delete a room from the panel. All three routes then answer `404 not_found` | Treat a room id as revocable, not permanent. On `404 not_found`, drop the room from the local list rather than retrying; the members will have been told out of band |
| `GET /api/v1/attachments/{id}` | The bytes were reachable until `ATTACH_TTL_DAYS` expired them | The operator can also delete an attachment before its TTL, from the panel. The route then answers `404 not_found`, exactly as it does after expiry | None. This is the same `404` a client already had to handle for an expired attachment, arriving sooner. Do not distinguish the two: a missing attachment and a pruned one are one answer, by design |
| Account deactivation, device revocation | Both already existed — deactivation in the stock admin, revocation as `DELETE /api/v1/me/devices/{id}` | Unchanged in effect. The panel now performs both through the same service functions the API uses, so an operator revocation has exactly the consequences a client revocation has: the tokens die, the one-time key material and the mailbox go, and any live socket closes with `4003` | None |

Nothing else about the panel is observable to a client. It is served at `ADMIN_PATH`
by the Django application mounted behind FastAPI, and every other path is still this
API's own `404`.

## What the security audit bounded

Each row below is a limit the security audit of phase 4 added. Every one refuses
something a client could previously do without bound, and every one is documented in
the route's own reference.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `POST /api/v1/auth/login` after five failed attempts on one name within fifteen minutes | Every attempt answered `401 invalid_credentials`; only the per-address limiter stood between a guesser with many addresses and the password | `429 {"code": "throttled", "detail": "Too many sign-in attempts for this name. Wait and try again."}` with `Retry-After` in seconds, for that name, until the cool-off ends. The lock applies to a name whether or not an account holds it, so it confirms nothing about existence, and a successful sign-in clears the count | Back off for `Retry-After` seconds and tell the user. Do not treat the refusal as a wrong password, and do not retry inside the window |
| `POST /api/v1/envelopes` to a device whose undelivered bytes would pass `MAILBOX_MAX_BYTES` (default 32 MiB) with this batch | Every item to a live device was queued; a mailbox had no ceiling | The device is refused whole — nothing is written for it and its sequence does not move — and named in a new `full_devices` list beside `stale_devices`; the rest of the batch proceeds and `accepted` counts only what was written | Read `full_devices` on every send. Keep a full device in the session set and retry its items once it has drained; a full device is live, not stale |
| `POST /api/v1/me/devicelog` when the account's log would pass `MAX_DEVICELOG_RECORDS` (default 10 000) records | Every well-formed append was stored; the log had no ceiling | `409 {"code": "devicelog_limit", "detail": "The device-list log of this account is full."}`, and nothing of the batch is stored | Append only on a device-set change or an identity rotation, as §J of `backend/CLIENT_CONTRACT.md` already says; a client that reaches the ceiling has a defect |

## Saturation now says so

One observable change came out of the performance, background-work and migration
audits. Everything else they touched — an index, a batched retention sweep, a pipelined
fan-out, the base64 the push stopped reproducing — leaves every request and every
response byte-identical: `backend/openapi.json` does not move.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| Any route, when the database connection pool has nothing free and the acquisition times out | `500 {"code": "server_error", "detail": "Internal error."}` — which tells a client the request itself was at fault and it should stop | `503 {"code": "unavailable", "detail": "The service is temporarily unavailable."}` — the same envelope the rate limiter already answers when Redis is gone, and a code every route already declared | Retry a `503 unavailable` with backoff. Nothing new to handle: every route already declared the status and the code, and a `500` was never something to retry. `backend/core/API.md` now names this as its third source |

Only a pool timeout reads this way. Django wraps every psycopg `OperationalError` in
one class, and a deadlock or a dropped connection is still `500 server_error`.

## What the reviews of phase 4 corrected

The contract, seam, architecture and panel reviews of phase 4 moved no route, no
status code and no response byte. Two things a client can observe are stated here for
the first time, and one thing this file said about itself was wrong.

### The document now declares the format of what it sends

Every id this API returns is a UUID and every `_date` it returns is a calendar day, but
`backend/openapi.json` declared each of them as a bare `string`. The same values were
already `"format": "uuid"` where a client *sends* them — every `{user_id}`,
`{device_id}` and `{room_id}` path parameter, `LoginIn.device_id`,
`OutgoingItemIn.device_id`, `ClaimIn.device_ids` and `AckIn.ids` — so a generated client
got one type on the way in and another on the way out for one value.

| Field | Old declaration | New declaration |
|---|---|---|
| `user_id` in `RegisterOut`, `RegisterScopeOut`, `FullScopeOut`, `DirectoryUserOut` | `string` | `string`, `"format": "uuid"` |
| `device_id` in `FullScopeOut`, `DeviceRegisteredOut`, `OwnDeviceOut`, `PeerDeviceOut`, `ClaimedBundleOut` | `string` | `string`, `"format": "uuid"` |
| `room_id` in `RoomCreatedOut`, `RoomOut` | `string` | `string`, `"format": "uuid"` |
| `id` in `EnvelopeOut` — the id `POST /api/v1/me/envelopes/ack` takes back | `string` | `string`, `"format": "uuid"` |
| `stale_devices`, `full_devices` in `SendOut` | `array` of `string` | `array` of `string`, `"format": "uuid"` |
| `created_date`, `last_active_date` in `OwnDeviceOut`, `updated_date` in `RoomOut` | `string` | `string`, `"format": "date"` |

**No response byte moved.** A UUID still serialises to the same canonical lowercase
form and a date to the same `YYYY-MM-DD`; only the published description changed.
`attachment_id` is deliberately absent from the table: an attachment id is a 43-character
capability, not a UUID, and it stays an unformatted string in the path and in the body
alike.

**Client action.** None, unless the client is generated from the schema and its
generator maps `format` to a type — a regenerated client may now type these fields as
`UUID` and `Date` rather than `String`. The values it receives are unchanged.

### `HEAD` and `OPTIONS` are refused

Before the rebuild, Django REST Framework answered `HEAD` on every route that served
`GET`, and answered `OPTIONS` with a metadata document this API never meant to publish.
FastAPI registers only the methods a route declares, so both now answer
`405 {"code": "method_not_allowed", "detail": "That method is not allowed."}` with
`Allow` naming the methods of the one route object.

**Client action.** None for a client that issues neither. A reachability probe uses
`GET /api/v1/health`, which is what it was always for.

The refusal itself is `_ROUTING_REFUSALS` in
[`backend/api/errors.py`](backend/api/errors.py), which is what puts the envelope on a
`405` where Starlette's own handler answers a bare body.

### One standing claim in this file was stale

The **Changed response fields** section opens "No success body changed." That was true
of the rebuild it describes and is no longer true of this file as a whole: the mailbox
ceiling the security audit added put a `full_devices` list into the `202` body of
`POST /api/v1/envelopes`, recorded under **What the security audit bounded**. The
sentence now says which change it is scoped to.

### The no-echo claim in `core/API.md` was wider than the behaviour

`backend/core/API.md` said "No error body ever echoes request input." Run 13's
malformed-input sweep found one fragment that does cross: a type message for a
malformed identifier names the offending character and its offset — "Input should be a
valid UUID, invalid character: found `z` at 35" — which `backend/messaging/API.md` had
been publishing as an example all along, so the two documents disagreed. The behaviour did not change and needs nothing from a client.
`core/API.md` now states the property that actually holds: no error body echoes a
value — no blob, no password, no token, no username, no identifier — and the one
fragment that crosses is a character of a malformed identifier, never of a payload.

## What the test suite found at the column boundaries

Runs 12 and 13 drove every route with malformed input. Run 12 covered `core`, `api`,
`accounts`, `devices`, `vault` and the migrations; run 13 covered `messaging`,
`attachments`, `voicerooms`, `realtime` and, through the contract suite, every route
of the document at once. Five routes answered `500` to input the schema existed to
filter, and all five are fixed. A `500` on input is a defect on this surface, never a
documented answer, so a client that branched on one was branching on a bug.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `PUT /api/v1/me/profile` and `PUT /api/v1/me/keybackup` with `version` above 2147483647 | `500 {"code": "server_error"}`. `version` lands in a 32-bit column and the schema bounded it below but not above, so the integer reached PostgreSQL as a `DataError` | `400 {"code": "invalid_request", "detail": {"version": [...]}}`. `accounts.schemas.BlobIn` now carries the ceiling, which both routes inherit. `version` = 2147483647 is still accepted and still stores | None, unless the client generated versions without a bound. The ceiling is the column's, not a policy: a client that increments a version per write will not reach it |
| `PUT /api/v1/me/devices/{device_id}/prekeys` with `cross_sig` and `bundle_version` both sent as `null` | `500 {"code": "server_error"}`. Both keys present satisfies the pairing guard, and `null` reached `Device.bundle_version`, which is not nullable | `400 {"code": "invalid_request", "detail": {"bundle_version": ["bundle_version must be a number when it is sent"]}}`. A sent `null` is half a pair in substance: a `cross_sig` stored against no version is one peers must reject | None. Clearing a signature against a version that is a number — `{"cross_sig": null, "bundle_version": 3}` — is unchanged and still `200` |
| `GET /api/v1/attachments/{attachment_id}` with a NUL byte in the id | `500 {"code": "server_error"}`. The same cause as the login defect below: PostgreSQL text carries no NUL, so psycopg refused the lookup rather than returning no row | `404 {"code": "not_found", "detail": "No such attachment."}`, the same answer a capability nobody holds gets. A capability id is base64url of 32 random bytes, so an id carrying the byte is an id nobody has | None. It was carried as AR-10 through run 12, because `attachments/` was outside that run's scope |
| `POST /api/v1/auth/login` with a NUL byte in `username` | `500 {"code": "server_error"}` on **anonymous** input. PostgreSQL text carries no NUL, so psycopg refused the lookup rather than returning no row | `401 {"code": "invalid_credentials"}`, the same answer every other unregistrable name gets | None. Deliberately not a `400`: `LoginIn` treats a badly shaped name as wrong credentials rather than a malformed request, and answering otherwise would tell an anonymous caller which names the column could have held |

`POST /api/v1/auth/register` was already correct — a control character in a username
has always been `400 invalid_request` there — so the two surfaces now agree: a name
that could never be registered is wrong credentials at login, and a malformed name is
a refusal at registration.

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
