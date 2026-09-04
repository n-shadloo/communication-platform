# API changes

Every observable change of the client contract since the pre-rebuild state, newest
phase first. The audience is the client developer. Each entry names the route or
field, the old behaviour, the new behaviour, and the client action. The current
contract is `backend/CLIENT_CONTRACT.md` and the per-app `backend/*/API.md`
references; this file records only what moved.

## Phase 2 — attachments and voice

The last run of the move to FastAPI
([ADR-0002](docs/architecture/decisions/0002-fastapi-as-the-only-http-api-surface.md)).
This run moves `POST /api/v1/attachments`, `GET /api/v1/attachments/{attachment_id}`,
`POST /api/v1/rooms`, `GET` and `PUT /api/v1/rooms/{room_id}`, and
`POST /api/v1/rooms/{room_id}/token`. Django REST Framework then leaves the project.
Every route of every app now answers through FastAPI.

No path, method, or success body changed. What changed is the error shape on these
six routes, four refusals that are reported differently, the body cap and the
deadline of each one, and what a path that no route serves answers.

### The error envelope reaches `attachments` and `voicerooms`

Every error these routes return is now `{"code": ..., "detail": ...}`, with `detail`
a string except for `invalid_request`, where it maps a field path to the list of
messages that failed. No error body echoes request input. The full vocabulary is the
table in `backend/core/API.md`; branch on `code`, never on `detail`.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| Validation failure on a room body | The bare Django REST Framework field-error object, with no `code` key: `{"name_blob": ["This field is required."]}` | `400 {"code": "invalid_request", "detail": {"name_blob": ["Field required"]}}` | Parse the envelope; read the field path as a dotted string |
| An undeclared field in a room body | `400 {"junk": "Unexpected field."}` | `400 {"code": "invalid_request", "detail": {"junk": ["Extra inputs are not permitted"]}}` | Send only `name_blob` |
| Validation messages | REST Framework's text, for example `"This field is required."` | Pydantic's text, for example `"Field required"` | Show `detail` values; never match on their text |
| Rate limited | `429 {"detail": "Request was throttled."}` | `429 {"code": "throttled", "detail": "Request was throttled."}` with a `Retry-After` header in seconds | Read `Retry-After` and back off; branch on `code` |
| Wrong method on one of these routes | `405 {"detail": "Method \"DELETE\" not allowed."}`, with `Allow` naming every method the route serves | `405 {"code": "method_not_allowed", "detail": "That method is not allowed."}`. `Allow` now names the methods of one route object, so on a path two methods share — `/api/v1/rooms/{room_id}` — it names one of them and not both | Branch on `code`. Do not read `Allow` as the complete method set of a path |
| Unhandled failure | Django's `500` page | `500 {"code": "server_error", "detail": "Internal error."}`, with no traceback and no detail | None |

One refusal is new: the counters for the `attachments` and `roomtoken` scopes now
live in Redis rather than in the Django cache layer, so a request that arrives while
that store is unreachable answers `503 {"code": "unavailable", ...}` instead of
failing as an unhandled error. The rates themselves are unchanged. Treat `503` as an
outage and `429` as backoff.

### Four refusals changed code

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| A malformed upload body — no `blob` part, a body that is not multipart, or a second part beside `blob` | `400 {"code": "bad_request", "detail": "Expected a single \`blob\` file."}` for a missing part; a second part was accepted and ignored | `400 {"code": "invalid_request", "detail": {"blob": ["Expected one multipart file part named \`blob\`."]}}` for all three. The code `bad_request` is retired | Replace the `bad_request` branch with `invalid_request`, and send exactly one part |
| A malformed `{room_id}` in a path | `404`, from the URL resolver | `400 {"code": "invalid_request", "detail": {"room_id": [...]}}` | Treat a malformed id as a client bug, not a missing resource |
| An unknown room | `GET` and the token mint returned `404 {"code": "not_found"}`; `PUT` returned `404` with an empty body | `404 {"code": "not_found", "detail": "No such room."}` on all three | Compare `code`, not the whole body, and parse the `PUT` refusal as JSON |
| `403 {"code": "device_scope_required"}` on the token mint | Documented, and unreachable in practice: every full-scope token names a device | Gone from the route. A register-scope token is `403 scope_forbidden`, which is what it always answered. The code stays in the vocabulary | Drop the `device_scope_required` branch |

`503 {"code": "voice_unconfigured"}` also gained a `detail` of `"Voice is not
configured."`; the code is unchanged.

### The upload takes a cap of its own

`POST /api/v1/attachments` was bounded at 70 MiB, which is what nginx admits, because
the same class covered every route the Django application still served. Its cap is
now the largest attachment bucket plus the multipart wrapper —
`67108864 + MULTIPART_OVERHEAD_BYTES`, 64 MiB + 8 KiB by default. A body between the
two answers `413 {"code": "payload_too_large", ...}` where it used to reach the
bucket check and answer `400 bad_bucket`. No legal upload is affected: the largest
one a client can send is exactly the largest bucket.

The four room routes and the attachment download move from that 70 MiB class to the
JSON class: 16 KiB, and a 15-second deadline rather than 120. The largest legal room
body is a 1024-byte name blob, about 1.4 KB encoded, so no legal request is affected.

### A path no route serves answers JSON

Django served every path FastAPI did not claim, so an unknown path under `/api/v1`
answered Django's own `404` page in `text/html`. Django now answers `ADMIN_PATH` and
nothing else, and every other unmatched path is
`404 {"code": "not_found", "detail": "No such route or resource."}` with the security
headers every other response carries. A client that distinguished a typo'd path from
a missing resource by content type must branch on `code` instead.

## Phase 2 — devices and messaging

The second run of the move to FastAPI
([ADR-0002](docs/architecture/decisions/0002-fastapi-as-the-only-http-api-surface.md)).
This run moves `PUT /api/v1/me/identity`, `GET /api/v1/users/{user_id}/identity`,
`POST` and `GET /api/v1/me/devices`, `PUT` and `DELETE
/api/v1/me/devices/{device_id}`, `PUT /api/v1/me/devices/{device_id}/prekeys`,
`GET /api/v1/me/devices/{device_id}/prekeys/count`, `POST /api/v1/me/devicelog`,
`GET /api/v1/users/{user_id}/devicelog`, `GET /api/v1/users/{user_id}/devices`,
`POST /api/v1/users/{user_id}/keys/claim`, `POST /api/v1/envelopes`,
`GET /api/v1/me/envelopes` and `POST /api/v1/me/envelopes/ack`. Only `attachments`
and `voicerooms` still answer from REST Framework.

No path, method, success body, header, or limit changed. What changed is the error
shape on these routes, three refusals that are now reported differently, and the
transaction a send runs in.

### The error envelope reaches `devices` and `messaging`

Every error these routes return is now `{"code": ..., "detail": ...}`, with `detail`
a string except for `invalid_request`, where it maps a field path to the list of
messages that failed. No error body echoes request input. The full vocabulary is the
table in `backend/core/API.md`; branch on `code`, never on `detail`.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| Validation failure on any of these routes | The bare Django REST Framework field-error object, with no `code` key: `{"ik_pub": ["invalid base64"]}`, and a nested item as `{"otpks": {"0": {"pub": [...]}}}` | `400 {"code": "invalid_request", "detail": {"ik_pub": ["invalid base64"]}}`, and a nested item as a dotted path: `{"otpks.0.pub": ["invalid base64"]}` | Parse the envelope, and read the field path as a dotted string rather than walking a nested object |
| Validation messages | REST Framework's text, for example `"This field is required."` | Pydantic's text, for example `"Field required"`. The length and base64 guards keep their own wording — `"invalid base64"`, `"bad key length"`, `"bad signature length"`, `"duplicate key_id"` | Show `detail` values; never match on their text |
| Stale identity version | `409 {"code": "stale_version"}` | `409 {"code": "stale_version", "detail": "Version must increase."}` | Compare `code`, not the whole body |
| No published identity for a peer | `404 {"code": "not_found"}` | `404 {"code": "not_found", "detail": "No published identity."}` | Compare `code`, not the whole body |
| Rate limited | `429 {"detail": "Request was throttled."}` | `429 {"code": "throttled", "detail": "Request was throttled."}` with a `Retry-After` header in seconds | Read `Retry-After` and back off; branch on `code` |
| Wrong method on one of these routes | `405 {"detail": "Method \"DELETE\" not allowed."}`, with `Allow` naming every method the route serves | `405 {"code": "method_not_allowed", "detail": "That method is not allowed."}`. `Allow` now names the methods of one route object, so on a path two methods share — `/api/v1/me/devices` — it names one of them and not both | Branch on `code`. Do not read `Allow` as the complete method set of a path |
| Unhandled failure | Django's `500` page | `500 {"code": "server_error", "detail": "Internal error."}`, with no traceback and no detail | None |

One refusal is new: the rate counters for these routes now live in Redis rather than
in the Django cache layer, so a request that arrives while that store is unreachable
answers `503 {"code": "unavailable", ...}` instead of failing as an unhandled error.
Treat `503` as an outage and `429` as backoff. The other pure-ASGI limits — the
request deadline and its own `503`, the body cap and its `413 payload_too_large`, the
`400 invalid_request` on an unlisted `Host`, and the three security headers on every
response — already applied to these routes through the transition mount and are
unchanged.

### Three refusals changed code

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| A malformed `{user_id}` or `{device_id}` in a path | `404`, from the URL resolver | `400 {"code": "invalid_request", "detail": {"user_id": [...]}}` | Treat a malformed id as a client bug, not a missing resource |
| A malformed ack body — a non-object, a non-list `ids`, more than 200 entries, or a non-UUID id | `400 {"code": "bad_request", "detail": "Malformed request."}` | `400 {"code": "invalid_request", "detail": {"ids.0": [...]}}`. The code `bad_request` is retired | Replace the `bad_request` branch with `invalid_request` |
| `403 {"code": "device_scope_required"}` on drain and ack | Documented, and unreachable in practice: the scope check already refused every token that names no device | Gone from these two routes. A register-scope token is `403 scope_forbidden`, which is what it always answered. The code stays in the vocabulary for `voicerooms` | Drop the `device_scope_required` branch from the mailbox routes |

### A send is one transaction

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `POST /api/v1/envelopes` with several accepted items | One transaction per accepted item. A failure part-way through left the earlier items queued, and a mailbox counter could end up ahead of its rows | One transaction for the whole call. Either every accepted item is queued or none is, and the counter advance commits with the rows it numbered | A retry after an unclear outcome can no longer find half a batch queued. Retrying a batch that did succeed still duplicates it, so keep de-duplicating on the receiving side |
| `stale_devices` | One entry per item that named an unreachable device, in the order the batch named them | Unchanged | None |

### An explicitly null request field

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `{"device_ids": null}` on claim | `400`; the field rejected an explicit null | Accepted, and it means the same as omitting the field: every live device of that user. An explicit `[]` still claims nothing | Omit a field you do not want to send, rather than sending null. `{"ids": null}` on ack is still a `400` |

### Unchanged

Every path and method; every success body, status and header of the moved routes,
including the `201` for registration and for the device-log append, the `202` for a
send, the `204` for a revoke and the `200` everywhere else; both device-list `ETag`s,
their `304` with an empty body, and what the tag covers; `log_head_seq`, `has_more`,
`head_seq`, `pruned_through` and `etag` in the bodies that carry them; the lenient
clamping of `after` and `limit` on the device log and of `limit` on the drain, which
still never error; every limit — 200 classical and 100 PQ prekeys per pool and per
payload, 100 claim ids, 50 device-log records, a 200-record log page, a 100-envelope
drain, a 200-id ack and a 256-item send batch — with the same public-key, signature
and base64 bounds; the registration refusal of `cross_sig` and `bundle_version`, and
the message that names the endpoint which accepts them; the first-device identity
exemption and `400 identity_required` past it; the device cap and its `409
device_limit`; `409 prekey_limit`, and the rule that a refused replenishment rotates
nothing; verbatim `cross_sig` with its nulls, and the omission of every PQ field from
a classical-only bundle; single consumption of a one-time prekey under concurrent
claims; the revocation cascade and the socket close behind it; `400 bad_bucket` with
no echo of the payload; and the throttle scope names, their environment variables and
their defaults.

## Phase 2 — the platform move

The HTTP surface is moving from Django REST Framework to FastAPI, one app at a time
([ADR-0002](docs/architecture/decisions/0002-fastapi-as-the-only-http-api-surface.md)),
and authentication is reissued on PyJWT with no token table
([ADR-0006](docs/architecture/decisions/0006-device-bound-tokens-on-pyjwt.md)). This
run moves `GET /api/v1/health`, the four `/api/v1/auth/*` routes, `GET /api/v1/users`,
`GET /api/v1/users/{user_id}/profile`, `GET` and `PUT /api/v1/me/profile`, and `GET`
and `PUT /api/v1/me/keybackup`. The routes of `devices`, `messaging`, `attachments`
and `voicerooms` still answer from REST Framework and are unchanged apart from the
`401` bodies below, which both stacks now share. `devices` and `messaging` moved in
the next run; the section above records what changed with them.

No path, method, or success body changed. What changed is the error shape, the status
of two outcomes, the logout call, and the rules around refresh tokens.

### The error envelope

Every error the moved routes return is `{"code": ..., "detail": ...}`. `detail` is a
string, except for `invalid_request`, where it maps a field path to the list of
messages that failed. No error body echoes request input. The full vocabulary is the
table in `backend/core/API.md`; branch on `code`, never on `detail`.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| Validation failure on a `vault` route | The bare Django REST Framework field-error object, with no `code` key: `{"version": ["This field is required."]}` | `400 {"code": "invalid_request", "detail": {"version": ["Field required"]}}` | Parse the envelope on every route, not only on `accounts` |
| Validation failure on an `accounts` route | `400 {"code": "invalid_request", "detail": {...}}` with REST Framework's messages | The same shape with Pydantic's messages, for example `["Field required"]` where REST Framework said `["This field is required."]` | Show `detail` values; never match on their text |
| Missing profile or key backup | `404 {"code": "not_found"}` on the key backup, with no `detail` | `404 {"code": "not_found", "detail": "No key backup yet."}` | Compare `code`, not the whole body |
| Stale version on the key backup | `409 {"code": "stale_version"}` | `409 {"code": "stale_version", "detail": "Version must increase."}` | Compare `code`, not the whole body |
| Rate limited | `429 {"detail": "Request was throttled."}` | `429 {"code": "throttled", "detail": "Request was throttled."}` with a `Retry-After` header in seconds | Read `Retry-After` and back off; branch on `code` |
| Wrong method on a moved route | `405 {"detail": "Method \"DELETE\" not allowed."}` | `405 {"code": "method_not_allowed", "detail": "That method is not allowed."}` with `Allow` | Branch on `code` |
| Unhandled failure | Django's `500` page | `500 {"code": "server_error", "detail": "Internal error."}`, with no traceback and no detail | None |

Three refusals are new, because the limits behind them are new. A body above the
route's cap answers `413 {"code": "payload_too_large", ...}`, counted as the bytes
arrive rather than read from `Content-Length`. A request that outlives its deadline,
and a throttled route whose counter store is unreachable, both answer
`503 {"code": "unavailable", ...}`; treat `503` as an outage and `429` as backoff. A
request whose `Host` header the server does not list answers
`400 {"code": "invalid_request", "detail": {"host": ["Unknown host."]}}`.

Every response now carries `X-Content-Type-Options: nosniff`, `Cache-Control:
no-store` and `Referrer-Policy: no-referrer`.

### The `401` bodies

These changed on **both** stacks, because both verify through one module now.

| Condition | Old body | New body | Client action |
|---|---|---|---|
| No `Authorization` header, or one that is not `Bearer <token>` | `401 {"detail": "Authentication credentials were not provided."}` | `401 {"code": "unauthenticated", "detail": "Authentication credentials were not provided."}`, with `WWW-Authenticate: Bearer` | Branch on `code` |
| Malformed, expired, or wrong-type token | `401 {"detail": "Given token not valid for any token type", "code": "token_not_valid", "messages": [...]}` | `401 {"code": "invalid_token", "detail": "Token is missing, malformed, or expired."}`. The `messages` array is gone | Replace the `token_not_valid` branch with `invalid_token`; drop any use of `messages` |
| Revoked device, stale generation, or deactivated account | `401 {"code": "token_revoked"}` | `401 {"code": "token_revoked", "detail": "Token is no longer valid."}` | None beyond comparing `code` |

### Validation is stricter

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| A JSON value of the wrong type in a request body | Coerced where possible: `"1"` and `true` both arrived as the integer `1` | `400 invalid_request`. A string is a string, an integer is an integer, and a boolean is a boolean | Send the declared JSON types |
| An unknown field in a `vault` body | Rejected, with the bare field-error object | Rejected, with the envelope | None beyond the envelope change |
| A non-UUID `{user_id}` in `GET /api/v1/users/{user_id}/profile` | `404`, from the URL resolver | `400 {"code": "invalid_request", "detail": {"user_id": [...]}}` | Treat a malformed id as a client bug, not a missing profile |
| A trailing slash on a moved path | `404` | `404`, unchanged. The server never redirects a trailing-slash mismatch | None |

### `username_taken` is a conflict

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `POST /api/v1/auth/register` with a name that exists | `400 {"code": "username_taken", "detail": "That username is taken."}` | `409 {"code": "username_taken", "detail": "That username is taken."}` | Move the branch from `400` to `409`. The concurrent race answers `409` too |

### Logout takes no body and answers `204`

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `POST /api/v1/auth/logout` | Required `{"refresh": "..."}`, blacklisted that one token if it belonged to the caller, and answered `205 Reset Content`. The access token stayed valid until it expired | Takes **no body** (one sent is ignored) and answers `204 No Content`. It advances the calling device's `token_generation`, so the presented access token **and every refresh token of that device** die immediately, and the device's sockets are closed | Send no body. Treat `204` as success, and discard both tokens. A retry with the same access token answers `401 token_revoked`, which is also success |

### Refresh tokens rotate against a generation, and reuse ends the family

There is no token table and no blacklist. A refresh token carries an `rgen` claim that
is compared with the device's `refresh_generation`.

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| Replaying a refresh token that was already rotated | `401`; the replayed token was blacklisted, and the newest pair kept working | `401 {"code": "token_revoked", ...}`, and `token_generation` advances: the newest access token and the newest refresh token die with it, and the device's sockets close. The account logs in again | **Never retry a refresh with the same token**, including after a timeout or a network error. On an unclear outcome, log in again |
| A successful refresh | Returned a new pair; the old refresh was blacklisted | Returns a new pair; the old refresh is behind the generation and is now a replay | Replace the stored refresh token on every call, before any retry |
| A register-scope token presented to `/auth/refresh` | `401 {"code": "token_revoked"}` | `401 {"code": "invalid_token", ...}`, refused before any database read | Branch on `invalid_token` as well |
| `POST /api/v1/auth/login` with a `device_id` | Left outstanding refresh tokens alone | Advances that device's `refresh_generation`, so a refresh token the device still held becomes a replay | Discard the tokens of the previous session when a login returns a new pair |
| Revoking a device, `DELETE /api/v1/me/devices/{id}` | Killed its tokens | Unchanged | None |

### Unchanged

Every path and method of the moved routes; every success body and status
(`201` for register, `200` for login, refresh, the directory, both profile calls and
both key-backup calls); the `register`/`full` scope split and what each scope reaches;
the timing-equalised login and the `403 account_inactive` response; the bucket rules
and `400 bad_bucket` with no echo; the `409 stale_version` rule on both versioned
blobs; the throttle scope names, their environment variables and their defaults; and
every route of `devices`, `messaging`, `attachments` and `voicerooms` apart from the
`401` bodies above.

A path that no route serves at all still answers Django's own `404` page
(`text/html`), not the envelope. That is the last piece of the transition and it
changes when the remaining apps move.

## Phase 1 — group protocol

Groups moved from MLS to pairwise Double Ratchet fan-out
([ADR-0001](docs/architecture/decisions/0001-pairwise-double-ratchet-group-fan-out.md)).
A group session is the set of pairwise sessions between the sender's device and every
member device, each started from the prekey bundles that
`POST /api/v1/users/{user_id}/keys/claim` already serves. The server keeps no group
object, no roster, no epoch, and no group key.

**The server has no counterpart for an MLS profile.** No endpoint accepts, stores, or
serves a key package, a Welcome, a commit, or any other MLS artefact, and none will.
The three routes below, one request field, one bucket set, and one variable are gone,
and `pruned_through` changed meaning.

### Removed routes

Each removed path now falls through the URL resolver. The response is Django's own
`404 Not Found` page (`text/html`), not the JSON error envelope.

| Route | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `PUT /api/v1/me/devices/{device_id}/keypackages` | Stored up to 100 consumable MLS key packages per device, plus one last-resort package, and returned `{"keypackage_count": n}`; `409 {"code": "keypackage_limit"}` at the cap | `404 Not Found` | Delete the upload path. Nothing replaces it: a group start needs no key package |
| `GET /api/v1/me/devices/{device_id}/keypackages/count` | Returned `{"keypackage_count": n}` for the calling device's consumable pool | `404 Not Found` | Delete the poll. Replenish one-time prekeys instead, on `GET /api/v1/me/devices/{device_id}/prekeys/count` (`otpk_count`, `pq_otpk_count`) |
| `POST /api/v1/users/{user_id}/keypackages/claim` | Returned one MLS key package per live device of the user as `{"keypackages": [{"device_id": …, "blob": …}]}`, consuming it, or the device's last-resort package when its pool was empty | `404 Not Found` | Start a group session by claiming PQXDH bundles from `POST /api/v1/users/{user_id}/keys/claim` for each member, exactly as for a direct message (`backend/CLIENT_CONTRACT.md` §F) |

### Removed request field

| Field | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `keypackages` in the body of `POST /api/v1/me/devices` | A required list, empty or up to 100 base64 blobs each padded to a key-package bucket, stored at registration; the client sends `"keypackages": []` | `400 Bad Request` with `{"keypackages": "Unexpected field."}`. The strict serializer rejects the key like any other unknown field, an empty list included | Remove the field from the registration body |

### Removed bucket set and variable

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `KEYPACKAGE_BUCKETS` in `backend/core/buckets.py`, `[4096, 16384]` | The exact padded sizes for key-package blobs; an off-bucket blob was `400 {"code": "bad_bucket"}` | The set no longer exists and no blob type pads to it. Every other bucket set is unchanged | Delete the constant and the padding code that used it |
| `KEYPACKAGE_TTL_DAYS` in the server environment, default 30 | The server deleted consumable key packages older than this many days and kept the last-resort package | The variable no longer exists; there is nothing to rotate | None for the client. The operator removes it from `.env` |

### Changed meaning

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `pruned_through` in the response of `GET /api/v1/me/envelopes` | A lost envelope may have been an MLS commit; the device was then permanently desynced from those groups and had to ask peers to remove and re-add it with a fresh Welcome | The shape is unchanged: the highest `seq` the TTL prune has deleted from this mailbox, 0 if never. A lost envelope may have carried a Double Ratchet message or a group control event; the device repairs each affected pairwise session through its authenticated repair path and asks a member for the current group control state | Replace the remove-and-re-add flow with the repair flow (`backend/CLIENT_CONTRACT.md` §H) |

### Unchanged

`POST /api/v1/envelopes` with up to 256 items per call and `accepted` and
`stale_devices` in the response, the envelope queue, `seq`, acknowledgement,
`ENVELOPE_TTL_DAYS`, the device-list `ETag`, the client-signed device log, the
revocation cascade, and the classical and ML-KEM prekey pools with their caps and
counts.
