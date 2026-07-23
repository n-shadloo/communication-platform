# devices API

The device registry and public-key distribution: registering a device with its key
bundle, listing and labelling devices, replenishing one-time prekeys and MLS key
packages, reading peers' device lists, and claiming key material to start sessions.
All paths are under `/api/v1`; requests and responses are JSON with base64-encoded
binary values; `Authorization: Bearer <access token>` is required everywhere (`full`
scope except where noted). Validation failures on this app return the DRF field-error
object directly, e.g. `400 {"ik_pub": ["invalid base64"]}`, with no `code` key; the
project-wide `401` bodies listed in `accounts/API.md` apply here too.

## Register a device / list my devices

**Method:** `POST`, `GET`
**Path:** `/api/v1/me/devices`

`POST` registers a cryptographic device: identity key, signed prekey with signature,
registration id, optional encrypted label, and optional initial one-time prekeys and
key packages, all in one transaction. It is the only endpoint that accepts a
register-scope token, and it responds with a full-scope token pair for the new device,
so a fresh install goes login → register device → full session in two calls. Live
devices are capped per account (default 10); revoked devices do not count.

`GET` (full scope only) lists the caller's live devices with their encrypted labels
and coarse dates, marking which entry is the calling device. The response carries an
`ETag`; poll with `If-None-Match` and treat `304` as "nothing changed".

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`; POST accepts register or full scope, GET requires full |
| `Content-Type` | POST only | `application/json` |
| `If-None-Match` | no (GET) | Previous `ETag` value |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body** (POST)

```json
{
  "ik_pub": "mNfJ2kLxWQ…",
  "spk_id": 1,
  "spk_pub": "aX9cR3tYvB…",
  "spk_sig": "Zk4wPq8sLm…",
  "registration_id": 4242,
  "label_blob": "cGFkZGVkLWxhYmVs…",
  "otpks": [ { "key_id": 1, "pub": "b2t0cGtl…" } ],
  "keypackages": [ "a2V5cGFja2FnZQ…" ]
}
```

Key fields decode to 32–256 bytes. `otpks` ≤ 200 items with unique `key_id`s;
`keypackages` ≤ 100, each exactly one key-package bucket (2048 or 8192 bytes);
`label_blob` optional, one label bucket (256 or 1024 bytes). Integer ids must fit a
32-bit column. The signed-prekey signature is stored and relayed, never verified
server-side; verification against `ik_pub` is the client's job.

**Responses**

### Registered — `201 Created` (POST)

```json
{
  "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611",
  "access": "eyJhbGciOiJIUzI1NiIs…",
  "refresh": "eyJhbGciOiJIUzI1NiIs…",
  "scope": "full"
}
```

### Listed — `200 OK` (GET)

```json
{
  "devices": [
    {
      "device_id": "9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611",
      "label_blob": "cGFkZGVkLWxhYmVs…",
      "created_date": "2026-07-20",
      "last_active_date": "2026-07-23",
      "this_device": true
    }
  ]
}
```

`label_blob` and `last_active_date` may be `null`. Header: `ETag: "5b3a9c…"`.

### Not modified — `304 Not Modified` (GET)

Empty body, when `If-None-Match` matches the current `ETag`.

### Invalid request — `400 Bad Request` (POST)

```json
{ "otpks": { "0": { "pub": ["invalid base64"] } } }
```

### Off-bucket label or key package — `400 Bad Request` (POST)

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

### Device cap reached — `409 Conflict` (POST)

```json
{ "code": "device_limit", "detail": "This account has too many devices." }
```

### Register-scope token on GET — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Relabel or revoke a device

**Method:** `PUT`, `DELETE`
**Path:** `/api/v1/me/devices/{device_id}`

`PUT` replaces the device's encrypted label. `DELETE` revokes the device: its token
generation is bumped (killing every outstanding access and refresh token), its
one-time prekeys, key packages, and queued envelopes are deleted, any live WebSocket
is closed with code 4003, and it disappears from device lists. Revocation is
permanent; a "re-added" device is a new registration. Any device of the account may
revoke any other (or itself).

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | PUT only | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `device_id` | UUID | yes | A live device belonging to the caller |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body** (PUT)

```json
{ "label_blob": "cGFkZGVkLWxhYmVs…" }
```

**Responses**

### Relabelled — `200 OK` (PUT)

Empty body.

### Revoked — `204 No Content` (DELETE)

Empty body.

### Invalid request — `400 Bad Request` (PUT)

```json
{ "label_blob": ["This field is required."] }
```

An off-bucket label is `400 {"code": "bad_bucket", "detail": "Invalid payload."}`.

### Unknown, foreign, or already-revoked device — `404 Not Found`

```json
{ "code": "not_found", "detail": "No such device." }
```

Another account's device id is a `404`, not a `403`, so existence is not confirmed.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Replenish prekeys

**Method:** `PUT`
**Path:** `/api/v1/me/devices/{device_id}/prekeys`

Uploads new one-time prekeys and/or rotates the signed prekey for the calling device.
Only the device itself may call this: the token's `device_id` must equal the path.
Re-uploading a `key_id` the device already stored is an idempotent retry, not an
error; a duplicated `key_id` inside one payload is a `400`. The stored pool is capped
at 200; a batch that would cross the cap is refused whole and, in that case, a
simultaneous `spk` rotation in the same request is not applied either.

Clients watch the count endpoint (or the `otpk_count` in this response) and replenish
when the pool runs low, since every peer claim consumes one.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, bound to `{device_id}` |
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `device_id` | UUID | yes | Must equal the token's own device id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{
  "spk": { "spk_id": 7, "pub": "aX9cR3tYvB…", "sig": "Zk4wPq8sLm…" },
  "otpks": [ { "key_id": 41, "pub": "b2t0cGtl…" } ]
}
```

Both fields optional; an empty body is a no-op that still returns the count.

**Responses**

### Replenished — `200 OK`

```json
{ "otpk_count": 173 }
```

### Invalid request — `400 Bad Request`

```json
{ "otpks": "duplicate key_id" }
```

### Not this device — `403 Forbidden`

```json
{ "code": "forbidden", "detail": "This token does not belong to that device." }
```

### Pool cap reached — `409 Conflict`

```json
{ "code": "prekey_limit", "detail": "Too many stored one-time prekeys for this device." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Prekey count

**Method:** `GET`
**Path:** `/api/v1/me/devices/{device_id}/prekeys/count`

Reports how many one-time prekeys the calling device still has stored. Same
self-only gate as replenishment.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, bound to `{device_id}` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `device_id` | UUID | yes | Must equal the token's own device id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Counted — `200 OK`

```json
{ "otpk_count": 173 }
```

### Not this device — `403 Forbidden`

```json
{ "code": "forbidden", "detail": "This token does not belong to that device." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Upload key packages

**Method:** `PUT`
**Path:** `/api/v1/me/devices/{device_id}/keypackages`

Uploads MLS key packages for the calling device (self-only, like prekeys). Each blob
must be exactly one key-package bucket. The store is capped at 100 per device; a
batch that would cross the cap is refused whole, so the client is told rather than
silently truncated.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, bound to `{device_id}` |
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `device_id` | UUID | yes | Must equal the token's own device id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{ "keypackages": [ "a2V5cGFja2FnZQ…", "c2Vjb25kLXBhY2s…" ] }
```

≤ 100 per request; optional (an empty upload returns the count).

**Responses**

### Uploaded — `200 OK`

```json
{ "keypackage_count": 42 }
```

### Invalid request — `400 Bad Request`

```json
{ "keypackages": ["Ensure this field has no more than 100 elements."] }
```

An off-bucket blob is `400 {"code": "bad_bucket", "detail": "Invalid payload."}`.

### Not this device — `403 Forbidden`

```json
{ "code": "forbidden", "detail": "This token does not belong to that device." }
```

### Store cap reached — `409 Conflict`

```json
{ "code": "keypackage_limit", "detail": "Too many stored key packages for this device." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Key-package count

**Method:** `GET`
**Path:** `/api/v1/me/devices/{device_id}/keypackages/count`

Reports how many key packages the calling device still has stored. Self-only.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, bound to `{device_id}` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `device_id` | UUID | yes | Must equal the token's own device id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Counted — `200 OK`

```json
{ "keypackage_count": 42 }
```

### Not this device — `403 Forbidden`

```json
{ "code": "forbidden", "detail": "This token does not belong to that device." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## List a user's devices

**Method:** `GET`
**Path:** `/api/v1/users/{user_id}/devices`

The public identity of a peer's live devices: device id, identity key, and
registration id, ordered by id — exactly what a sender needs to fan a message out to
every device. Labels, dates, and activity are omitted; those belong to the owner. The
response carries an `ETag` (also mirrored in the body), and an unknown user is
indistinguishable from a user with no live devices.

Poll with `If-None-Match` before encrypting to a peer; a changed tag means a device
was added or removed and session state should be refreshed.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `If-None-Match` | no | Previous `ETag` value |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Account whose devices are listed |

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
  "devices": [
    {
      "device_id": "2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f",
      "ik_pub": "mNfJ2kLxWQ…",
      "registration_id": 4242
    }
  ],
  "etag": "\"5b3a9c1d7e2f4a6b8c0d1e2f3a4b5c6d\""
}
```

Header: `ETag: "5b3a9c1d7e2f4a6b8c0d1e2f3a4b5c6d"`. An unknown or deactivated user
yields `{"devices": [], "etag": …}` with `200`.

### Not modified — `304 Not Modified`

Empty body.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Claim prekey bundles

**Method:** `POST`
**Path:** `/api/v1/users/{user_id}/keys/claim`

Returns an X3DH bundle for each of the target user's live devices, atomically
consuming one one-time prekey per device (each prekey is handed out at most once,
even under concurrent claims). When a device's pool is empty the bundle is served
without the `otpk` field; the client falls back per protocol. Claiming your own
`user_id` is the normal self-sync path.

Call it when starting a session with a peer. An explicit `"device_ids": []` claims
nothing — the empty list is honoured, not treated as "all" — so batch carefully.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Owner of the devices whose prekeys are claimed |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{ "device_ids": ["2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f"] }
```

Optional (≤ 100 ids). Omitted entirely means "all live devices of that user".

**Responses**

### Claimed — `200 OK`

```json
{
  "bundles": [
    {
      "device_id": "2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f",
      "registration_id": 4242,
      "ik_pub": "mNfJ2kLxWQ…",
      "spk_id": 7,
      "spk_pub": "aX9cR3tYvB…",
      "spk_sig": "Zk4wPq8sLm…",
      "otpk": { "key_id": 41, "pub": "b2t0cGtl…" }
    }
  ]
}
```

`otpk` is absent when that device's pool is empty. An unknown user or one with no
live devices yields `{"bundles": []}` with `200`.

### Invalid request — `400 Bad Request`

```json
{ "device_ids": { "0": ["Must be a valid UUID."] } }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `claim`, default 120/min.

## Claim key packages

**Method:** `POST`
**Path:** `/api/v1/users/{user_id}/keypackages/claim`

Consumes and returns one stored MLS key package per targeted live device (oldest
first, each handed out exactly once). Devices with an empty store are simply absent
from the response; an exhausted store is not an error. Used when adding a user's
devices to a group.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Owner of the devices whose key packages are claimed |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

```json
{ "device_ids": ["2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f"] }
```

Optional, same semantics as the prekey claim.

**Responses**

### Claimed — `200 OK`

```json
{
  "keypackages": [
    { "device_id": "2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f", "blob": "a2V5cGFja2FnZQ…" }
  ]
}
```

### Invalid request — `400 Bad Request`

```json
{ "device_ids": ["Ensure this field has no more than 100 elements."] }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `claim`, default 120/min.
