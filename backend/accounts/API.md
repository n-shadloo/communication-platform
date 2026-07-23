# accounts API

Account lifecycle and identity: registration, login, token refresh and logout, the
user directory, and encrypted profile blobs. All paths are under `/api/v1`. Requests
and responses are JSON; binary values are base64 strings. Unless an endpoint says
otherwise, it requires `Authorization: Bearer <access token>` with `full` scope, and
errors use the `{"code": "...", "detail": ...}` envelope. Three responses can appear
on any authenticated endpoint and are not repeated per section: `401
{"detail": "Authentication credentials were not provided."}` for a missing token,
`401 {"detail": "Given token not valid for any token type", "code": "token_not_valid",
"messages": [...]}` for a malformed or expired token, and `401 {"code": "token_revoked"}`
for a token whose device was revoked or rotated.

## Register an account

**Method:** `POST`
**Path:** `/api/v1/auth/register`

Creates an account in the inactive state. The server owner activates accounts through
the admin; until then the account cannot log in past the password check. Usernames are
lowercased before validation and storage, so `BoB` and `bob` are the same account.

A client calls this once, shows the "awaiting activation" state on the `403
account_inactive` login response, and retries login later. There is nothing to poll;
activation is a human action.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{
  "username": "alice",
  "password": "correct-horse-battery-staple"
}
```

`username`: 3–32 chars of `[a-z0-9_]` (case-insensitive input, stored lowercase).
`password`: ≥10 chars, not a common password, ≤256 chars. Unknown fields are rejected.

**Responses**

### Created — `201 Created`

```json
{ "user_id": "6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10" }
```

### Invalid request — `400 Bad Request`

```json
{ "code": "invalid_request", "detail": { "password": ["This field is required."] } }
```

### Username taken — `400 Bad Request`

```json
{ "code": "username_taken", "detail": "That username is taken." }
```

Also returned when two concurrent registrations race on the same name.

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `register`, default 10/hour per client.

## Log in

**Method:** `POST`
**Path:** `/api/v1/auth/login`

Verifies the password and issues tokens. With a `device_id` naming a live device of
this account, the response is a full-scope access/refresh pair bound to that device.
Without one (first login, or a revoked/foreign device id), the response is a
short-lived register-scope access token whose only power is `POST /api/v1/me/devices`.

Unknown usernames and wrong passwords return the same body, and unknown usernames
still pay for a real Argon2 verification, so the two cases are not distinguishable by
response or by timing. Activation state is only revealed after a correct password.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{
  "username": "alice",
  "password": "correct-horse-battery-staple",
  "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611"
}
```

`device_id` is optional.

**Responses**

### Full-scope pair — `200 OK`

```json
{
  "access": "eyJhbGciOiJIUzI1NiIs…",
  "refresh": "eyJhbGciOiJIUzI1NiIs…",
  "user_id": "6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10",
  "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611",
  "scope": "full"
}
```

### Register-scope token — `200 OK`

```json
{
  "access": "eyJhbGciOiJIUzI1NiIs…",
  "user_id": "6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10",
  "scope": "register"
}
```

### Invalid request — `400 Bad Request`

```json
{ "code": "invalid_request", "detail": { "device_id": ["Must be a valid UUID."] } }
```

### Wrong credentials — `401 Unauthorized`

```json
{ "code": "invalid_credentials", "detail": "Username or password is incorrect." }
```

### Awaiting activation — `403 Forbidden`

```json
{ "code": "account_inactive", "detail": "This account is awaiting activation." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `login`, default 20/hour.

## Refresh tokens

**Method:** `POST`
**Path:** `/api/v1/auth/refresh`

Rotates a full-scope refresh token: the presented token is blacklisted and a new
access/refresh pair is issued for the same device. The device and account are
re-checked, so revocation, a bumped token generation, or deactivation all end the
session here even if the refresh token itself is still validly signed.

Clients should refresh shortly before access expiry (default 15 minutes) and must
replace the stored refresh token on every call; replaying an already-rotated token is
a 401.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{ "refresh": "eyJhbGciOiJIUzI1NiIs…" }
```

**Responses**

### Rotated — `200 OK`

```json
{ "access": "eyJhbGciOiJIUzI1NiIs…", "refresh": "eyJhbGciOiJIUzI1NiIs…" }
```

### Missing or malformed token — `401 Unauthorized`

```json
{ "code": "invalid_token", "detail": "Refresh token is missing or malformed." }
```

Also covers expired and already-blacklisted tokens.

### Revoked — `401 Unauthorized`

```json
{ "code": "token_revoked", "detail": "Token is no longer valid." }
```

Returned for a register-scope token, a revoked or deleted device, a stale token
generation, or a deactivated account, without distinguishing them.

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `refresh`, default 120/hour.

## Log out

**Method:** `POST`
**Path:** `/api/v1/auth/logout`

Blacklists the presented refresh token if it belongs to the calling account.
Idempotent: an already-expired or already-blacklisted token still yields `205`. A
refresh token belonging to another account is silently ignored, so logout cannot be
used cross-account. The access token stays valid until it expires; clients should
discard both tokens locally.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{ "refresh": "eyJhbGciOiJIUzI1NiIs…" }
```

**Responses**

### Logged out — `205 Reset Content`

Empty body.

### Invalid request — `400 Bad Request`

```json
{ "code": "invalid_request", "detail": { "refresh": ["This field is required."] } }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## List users

**Method:** `GET`
**Path:** `/api/v1/users`

Returns every activated account, ordered by username: this is a small private server
and the directory is how clients pick conversation partners. Entries carry only the id
and username; nothing about devices or activity. Inactive accounts are absent.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Listed — `200 OK`

```json
{
  "users": [
    { "user_id": "6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10", "username": "alice" },
    { "user_id": "b3a91c77-2e5d-4f28-a1c9-8d64e0f3b522", "username": "bob" }
  ]
}
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Read a user's profile

**Method:** `GET`
**Path:** `/api/v1/users/{user_id}/profile`

Returns the opaque profile blob another user published (display name, avatar, and so
on, encrypted client-side) with its version. The server cannot read it; clients
decrypt with material exchanged in-band. Clients cache by `version` and refetch when
a peer announces a change.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Account whose profile is requested |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Found — `200 OK`

```json
{ "blob": "q83vEjRWeJq83vEjRWeJ…", "version": 3 }
```

### No profile — `404 Not Found`

```json
{ "code": "not_found", "detail": "No profile for that user." }
```

Also returned when the user does not exist or is deactivated.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Read or write my profile

**Method:** `GET`, `PUT`
**Path:** `/api/v1/me/profile`

`GET` returns the caller's own stored profile blob. `PUT` replaces it; the blob must
decode to exactly one profile bucket (1024 or 4096 bytes) and the version must be
strictly greater than the stored one. Version monotonicity is what lets several of
the caller's devices write without a stale device clobbering a newer profile: the
losing writer gets `409 stale_version`, refetches, and reapplies.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | PUT only | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body** (PUT)

```json
{ "blob": "q83vEjRWeJq83vEjRWeJ…", "version": 4 }
```

**Responses**

### Read — `200 OK` (GET)

```json
{ "blob": "q83vEjRWeJq83vEjRWeJ…", "version": 3 }
```

### Written — `200 OK` (PUT)

Empty body.

### No profile yet — `404 Not Found` (GET)

```json
{ "code": "not_found", "detail": "No profile yet." }
```

### Invalid request — `400 Bad Request` (PUT)

```json
{ "code": "invalid_request", "detail": { "version": ["This field is required."] } }
```

### Off-bucket blob — `400 Bad Request` (PUT)

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

The rejected payload is never echoed.

### Stale version — `409 Conflict` (PUT)

```json
{ "code": "stale_version", "detail": "Version must increase." }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.
