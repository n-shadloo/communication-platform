# API changes

Every observable change of the client contract since the pre-rebuild state, newest
phase first. The audience is the client developer. Each entry names the route or
field, the old behaviour, the new behaviour, and the client action. The current
contract is `backend/CLIENT_CONTRACT.md` and the per-app `backend/*/API.md`
references; this file records only what moved.

## Phase 2 — platform

The HTTP surface is moving from Django REST Framework to FastAPI, one app at a time
([ADR-0002](docs/architecture/decisions/0002-fastapi-as-the-only-http-api-surface.md)),
and authentication is reissued on PyJWT with no token table
([ADR-0006](docs/architecture/decisions/0006-device-bound-tokens-on-pyjwt.md)). This
run moves `GET /api/v1/health`, the four `/api/v1/auth/*` routes, `GET /api/v1/users`,
`GET /api/v1/users/{user_id}/profile`, `GET` and `PUT /api/v1/me/profile`, and `GET`
and `PUT /api/v1/me/keybackup`. The routes of `devices`, `messaging`, `attachments`
and `voicerooms` still answer from REST Framework and are unchanged apart from the
`401` bodies below, which both stacks now share.

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
