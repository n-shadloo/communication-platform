# devices API

The device registry and public-key distribution: publishing the account's
cross-signing identity, registering a device with its signed key bundle, listing and
labelling devices, replenishing classical and ML-KEM one-time prekeys and MLS key
packages, maintaining the client-signed device-list log, reading peers' device lists,
and claiming key material to start sessions. All paths are under `/api/v1`; requests
and responses are JSON with base64-encoded binary values;
`Authorization: Bearer <access token>` is required everywhere (`full` scope except
where noted). Validation failures on this app return the DRF field-error object
directly, e.g. `400 {"ik_pub": ["invalid base64"]}`, with no `code` key; the
project-wide `401` bodies listed in `accounts/API.md` apply here too.

**Nothing in this app is verified server-side.** Cross-signatures, prekey signatures,
identity self-signatures, and device-log hash chains are stored and relayed as opaque
bytes; every length and version check below is a malformed-input or anti-accident
guard, never a security control. The verifying party is always the peer client —
`CLIENT_CONTRACT.md` specifies that half.

## Publish my cross-signing identity

**Method:** `PUT`
**Path:** `/api/v1/me/identity`

Uploads the account's cross-signing public keys: the master key, the self-signing key
(signs device bundles), the user-signing key (signs other users' master keys after
out-of-band verification), and `master_sig`, the master key's Ed25519 signature over
the canonical encoding of the two subkeys. All are opaque to the server. The `version`
must be strictly greater than the stored one; the check exists so a stale client
cannot accidentally clobber a newer identity — a modified server would simply not
apply it, so clients must detect identity changes themselves (fetch + compare against
the out-of-band-verified master key).

A fresh account publishes its identity immediately after registering its first device
(the first registration is the only one allowed without a published identity — see
device registration below).

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `application/json` |

**Request body**

```json
{
  "master_pub": "bU1hc3RlcktleQ…",
  "self_signing_pub": "c1NlbGZTaWdu…",
  "user_signing_pub": "dVVzZXJTaWdu…",
  "master_sig": "Z01hc3RlclNpZw…",
  "version": 1
}
```

Keys decode to 32–256 bytes (Ed25519 keys are 32); `master_sig` must decode to exactly
64 bytes. `version` fits a 32-bit column.

**Responses**

### Published — `200 OK`

Empty body.

### Invalid request — `400 Bad Request`

```json
{ "master_sig": ["bad signature length"] }
```

### Stale version — `409 Conflict`

```json
{ "code": "stale_version" }
```

Sent when `version` ≤ the stored version; the stored identity is unchanged.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Fetch a user's cross-signing identity

**Method:** `GET`
**Path:** `/api/v1/users/{user_id}/identity`

Returns the user's published identity verbatim — including after a master-key change:
the server never smooths over, merges, or hides a substitution, because surfacing the
new bytes is exactly what lets the client raise its safety-number-style alarm and
block the conversation pending re-verification.

**The client must verify signatures over the exact key bytes in this response, never
look a key up by a server-supplied identifier and trust that instead.** That mistake
was CVE-2022-39250 in matrix-js-sdk (cross-signing identity injection, CVSS 8.6):
checking and signing were two separate steps, so a malicious homeserver could
substitute the key between them. The canonical encodings in this API are
self-contained so no such indirection exists.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Account whose identity is fetched |

**Responses**

### Found — `200 OK`

```json
{
  "master_pub": "bU1hc3RlcktleQ…",
  "self_signing_pub": "c1NlbGZTaWdu…",
  "user_signing_pub": "dVVzZXJTaWdu…",
  "master_sig": "Z01hc3RlclNpZw…",
  "version": 3
}
```

### No published identity, unknown or deactivated user — `404 Not Found`

```json
{ "code": "not_found" }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## The canonical device-bundle encoding (client-computed; the server never parses it)

The self-signing key signs every device's bundle. The signed payload is the ASCII
domain separator `chat:v1:device-bundle` followed by the length-prefixed concatenation
(4-byte big-endian length before each field) of, in this exact order:

| # | Field | Encoding |
|---|-------|----------|
| 1 | `user_id` | 16 bytes, UUID raw |
| 2 | `device_id` | 16 bytes, UUID raw |
| 3 | `ik_pub` | raw bytes |
| 4 | `spk_id` | 4 bytes, big-endian |
| 5 | `spk_pub` | raw bytes |
| 6 | `pq_spk_id` | 4 bytes, big-endian; zero-length field if absent |
| 7 | `pq_spk_pub` | raw bytes; zero-length field if absent |
| 8 | `registration_id` | 4 bytes, big-endian |
| 9 | `bundle_version` | 4 bytes, big-endian |

The encoding embeds the key **bytes**, never key identifiers, so verifying it commits
the verifier to exactly the material the server served (the CVE-2022-39250 lesson
above). `bundle_version` is bumped by the client whenever any signed field changes, so
a stale signature is detectable client-side.

> **Load-bearing coupling:** rotating the signed prekey (`spk`) changes field 5, so
> the existing `cross_sig` goes stale. A client that rotates `spk` without supplying a
> fresh `cross_sig` and incremented `bundle_version` **in the same request** will be
> correctly rejected by peers. See "Replenish prekeys" below.

## Register a device / list my devices

**Method:** `POST`, `GET`
**Path:** `/api/v1/me/devices`

`POST` registers a cryptographic device: identity key, signed prekey with signature,
registration id, the device's `cross_sig` (the self-signing key's signature over the
canonical bundle above) and `bundle_version`, optional ML-KEM-768 signed prekey and
one-time prekeys, optional encrypted label, and optional initial classical one-time
prekeys and key packages, all in one transaction. It is the only endpoint that accepts
a register-scope token, and it responds with a full-scope token pair for the new
device, so a fresh install goes login → register device → publish identity → full
session. Live devices are capped per account (default 10); revoked devices do not
count.

`cross_sig` and `bundle_version` are required, and any registration past the account's
first live device additionally requires a published identity (`400
{"code":"identity_required"}` otherwise — the first device is exempt because a
register-scope token cannot have published one yet). Both requirements are
completeness checks that stop an unverifiable device entering the system by client
bug; they are **not** security controls — a modified server would skip them, and peers
must reject unsigned devices regardless.

`GET` (full scope only) lists the caller's live devices with their encrypted labels
and coarse dates, marking which entry is the calling device, plus `log_head_seq`, the
head of the account's device-list log (null when empty). The response carries an
`ETag`; poll with `If-None-Match` and treat `304` as "nothing changed". The tag covers
the live device set **and** the device-log head, so a log append also invalidates it —
expect more frequent invalidation than under the device-set-only tag.

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
  "cross_sig": "eENyb3NzU2ln…",
  "bundle_version": 1,
  "pq_spk": { "spk_id": 1, "pub": "cVBxU3BrS2V5…", "sig": "c1BxU2ln…" },
  "pq_otpks": [ { "key_id": 1, "pub": "cVBxT3Rwaw…" } ],
  "label_blob": "cGFkZGVkLWxhYmVs…",
  "otpks": [ { "key_id": 1, "pub": "b2t0cGtl…" } ],
  "keypackages": [ "a2V5cGFja2FnZQ…" ]
}
```

Classical key fields decode to 32–256 bytes; `cross_sig` and `pq_spk.sig` to exactly
64 bytes (Ed25519); PQ public keys to exactly 1184 bytes (an ML-KEM-768 encapsulation
key is fixed-size, so the exact check rejects nothing a real client would send).
`otpks` ≤ 200 and `pq_otpks` ≤ 100 items with unique `key_id`s per list;
`keypackages` ≤ 100, each exactly one key-package bucket (4096 or 16384 bytes);
`label_blob` optional, one label bucket (256 or 1024 bytes). Integer ids must fit a
32-bit column. Every signature is stored and relayed, never verified server-side;
verification is the peer client's job.

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
  ],
  "log_head_seq": 4
}
```

`label_blob`, `last_active_date`, and `log_head_seq` may be `null`. Header:
`ETag: "5b3a9c…"`.

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

### No published identity (second device onward) — `400 Bad Request` (POST)

```json
{ "code": "identity_required", "detail": "Publish a cross-signing identity before adding another device." }
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
one-time prekeys (classical and ML-KEM), key packages (last-resort included), and
queued envelopes are deleted in one transaction, any live WebSocket is closed with
code 4003, and it disappears from device lists. Revocation is permanent; a "re-added"
device is a new registration. Any device of the account may revoke any other (or
itself). The client appends a device-list log record for the removal
(CLIENT_CONTRACT.md §J).

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

Uploads new one-time prekeys (classical and/or ML-KEM) and/or rotates the signed
prekeys for the calling device. Only the device itself may call this: the token's
`device_id` must equal the path. Re-uploading a `key_id` the device already stored is
an idempotent retry, not an error; a duplicated `key_id` inside one payload is a
`400`. The classical pool is capped at 200 and the PQ pool at 100; a batch that would
cross either cap is refused whole and, in that case, nothing else in the request is
applied either — no prekey rotation, no signature update.

> **Rotating `spk` stales your `cross_sig`.** The signed prekey is a field of the
> canonical device bundle, so replacing it invalidates the stored cross-signature.
> Send a fresh `cross_sig` and an incremented `bundle_version` **in the same call**,
> or peers fetching your bundle will correctly reject this device. The server stores
> whatever it is given and never checks the pairing — only peers can, so there is no
> server error to save a client that forgets.

Clients watch the count endpoint (or the `otpk_count` in this response) and replenish
when the pools run low, since every peer claim consumes one of each.

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
  "cross_sig": "eENyb3NzU2ln…",
  "bundle_version": 2,
  "pq_spk": { "spk_id": 3, "pub": "cVBxU3BrS2V5…", "sig": "c1BxU2ln…" },
  "pq_otpks": [ { "key_id": 12, "pub": "cVBxT3Rwaw…" } ],
  "otpks": [ { "key_id": 41, "pub": "b2t0cGtl…" } ]
}
```

All fields optional; an empty body is a no-op that still returns the count. PQ public
keys must decode to exactly 1184 bytes; `cross_sig` and `pq_spk.sig` to exactly 64.

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

Reports how many one-time prekeys — classical and ML-KEM — the calling device still
has stored. Same self-only gate as replenishment.

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
{ "otpk_count": 173, "pq_otpk_count": 88 }
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
must be exactly one key-package bucket (4096 or 16384 bytes — sized for PQ
ciphersuites; pad accordingly). The consumable store is capped at 100 per device; a
batch that would cross the cap is refused whole, so the client is told rather than
silently truncated.

With `"is_last_resort": true` the request must carry exactly one blob, which
**replaces** the device's single last-resort package (at most one exists; re-uploading
after a reinstall is idempotent). The last-resort package is what claims fall back to
when the consumable pool is exhausted — it is served without being deleted, at a
forward-secrecy cost on the initial group join (see the claim endpoint), which is why
a healthy client keeps the consumable pool stocked and treats the last-resort package
as insurance, not inventory. It lives outside the 100-cap and outside
`keypackage_count`.

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
{ "keypackages": [ "a2V5cGFja2FnZQ…", "c2Vjb25kLXBhY2s…" ], "is_last_resort": false }
```

≤ 100 per request; both fields optional (an empty upload returns the count);
`is_last_resort: true` requires exactly one blob.

**Responses**

### Uploaded — `200 OK`

```json
{ "keypackage_count": 42 }
```

The count covers the consumable pool only — the last-resort package is never counted,
because it never leaves and would otherwise mask exhaustion.

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

Reports how many consumable key packages the calling device still has stored (the
last-resort package is excluded). Self-only.

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

The public identity of a peer's live devices: device id, identity key, registration
id, cross-signature, and bundle version, ordered by id — what a sender needs to fan a
message out to every device *and* to verify each device against the owner's published
identity. `cross_sig` is served verbatim, `null` included: a device that was never
cross-signed must be visible as unsigned so peers can refuse it (the server never
substitutes or synthesizes a signature). The response also carries `log_head_seq`, the
head of the user's device-list log. Labels, dates, and activity are omitted; those
belong to the owner. The response carries an `ETag` (also mirrored in the body), and
an unknown user is indistinguishable from a user with no live devices.

Poll with `If-None-Match` before encrypting to a peer; a changed tag means a device
was added or removed **or the device log was appended to** (the tag covers both), and
session state / log-head comparison should be refreshed.

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
      "registration_id": 4242,
      "cross_sig": "eENyb3NzU2ln…",
      "bundle_version": 2
    }
  ],
  "etag": "\"5b3a9c1d7e2f4a6b8c0d1e2f3a4b5c6d\"",
  "log_head_seq": 4
}
```

Header: `ETag: "5b3a9c1d7e2f4a6b8c0d1e2f3a4b5c6d"`. `cross_sig` and `log_head_seq`
may be `null`. An unknown or deactivated user yields `{"devices": [], "etag": …,
"log_head_seq": null}` with `200`.

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

Returns a hybrid PQXDH bundle for each of the target user's live devices, atomically
consuming one classical and (when the device has PQ material) one ML-KEM one-time
prekey per device (each key is handed out at most once, even under concurrent
claims). When a device's classical pool is empty the bundle is served without the
`otpk` field; the client falls back per protocol. Claiming your own `user_id` is the
normal self-sync path.

**When a device holds no PQ signed prekey, every PQ field is omitted from its bundle
— never null-filled, zeroed, or substituted with classical material — so a
classical-only bundle is visibly classical-only.** Deciding whether to refuse it or
proceed with a clearly-flagged classical-only session is the client's job
(CLIENT_CONTRACT.md §F: never silently downgrade).

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
      "cross_sig": "eENyb3NzU2ln…",
      "bundle_version": 2,
      "pq_spk_id": 3,
      "pq_spk_pub": "cVBxU3BrS2V5…",
      "pq_spk_sig": "c1BxU2ln…",
      "pq_otpk": { "key_id": 12, "pub": "cVBxT3Rwaw…" },
      "otpk": { "key_id": 41, "pub": "b2t0cGtl…" }
    }
  ]
}
```

`otpk` is absent when that device's classical pool is empty; `pq_otpk` when its PQ
pool is empty; all four `pq_*` fields when the device has no PQ signed prekey.
`cross_sig` is `null` for a device that was never cross-signed (verify before
encrypting — CLIENT_CONTRACT.md §C/§E). An unknown user or one with no live devices
yields `{"bundles": []}` with `200`.

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

Returns one MLS key package per targeted live device. A consumable (non-last-resort)
package is preferred: oldest first, deleted on claim, each handed out exactly once.
When a device's consumable pool is exhausted, its **last-resort** package is served
instead — **without being deleted**, so the device stays addable to groups. A reused
last-resort package weakens forward secrecy for the initial group join (every join
that used it shares one KEM secret, so a later compromise of that key exposes each
such join's Welcome); it is a fallback, not an equivalent. Devices with neither are
simply absent from the response; an exhausted store is not an error. Used when adding
a user's devices to a group.

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

## Append to my device-list log

**Method:** `POST`
**Path:** `/api/v1/me/devicelog`

Appends client-signed, hash-chained records to the account's device-list log. The
client appends one on every device-set change (add, remove, revoke) and on identity
rotation. Record contents are client-defined and opaque — the expected structure is
`prev_hash`, a hash of the canonical device-set encoding, the current identity
`version`, the record `seq`, a coarse timestamp, and an Ed25519 signature by the
self-signing key over all of it — but **the server never parses or validates any of
that, including the hash chain**. A record whose `prev_hash` links to nothing is
accepted and served verbatim; server-side chain validation would be fake enforcement
that trains clients to skip the head comparison which actually detects equivocation.
Two honest clients holding different heads for the same user is cryptographic proof
the server equivocated — detection, not prevention, and only once two clients
actually compare (clients gossip heads inside ordinary E2EE messages).

Appending changes the account's device-list `ETag`, so polling peers re-fetch and see
the new head.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `application/json` |

**Request body**

```json
{ "records": [ { "blob": "ZGV2aWNlbG9nLXJlY29yZA…" } ] }
```

1–50 records, each exactly one device-log bucket (256 or 1024 bytes).

**Responses**

### Appended — `201 Created`

```json
{ "first_seq": 5, "last_seq": 5 }
```

Sequence numbers are server-assigned, per-user, contiguous within a batch, starting
at 0.

### Off-bucket record — `400 Bad Request`

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
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

## Read a user's device-list log

**Method:** `GET`
**Path:** `/api/v1/users/{user_id}/devicelog`

Keyset-paged read of a user's device-list log, records served byte-identically in
seq order — no repair, no reordering, no dropping of non-linking records (see the
append endpoint for why). On fetch, the client verifies the head signature and that
the head **extends** the last head it saw for that user; a fork is proof of server
equivocation (CLIENT_CONTRACT.md §C/§J).

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `user_id` | UUID | yes | Account whose log is read |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `after` | int | no | start of log | Return records with `seq` greater than this |
| `limit` | int | no | 200 | Page size, clamped into [1, 200] |

A non-numeric `after` falls back to the start; a bad limit falls back to the cap —
never a `500`.

**Request body**

None.

**Responses**

### Read — `200 OK`

```json
{
  "records": [ { "seq": 4, "blob": "ZGV2aWNlbG9nLXJlY29yZA…" } ],
  "has_more": false,
  "head_seq": 4
}
```

`head_seq` is `null` and `records` empty for an empty log, an unknown user, or a
deactivated user.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.
