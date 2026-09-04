# messaging API

The durable message queue: fan-out send, per-device drain, and acknowledgement. Every
payload is an opaque, padded, client-encrypted blob in an exact envelope bucket
(1024, 4096, 16384, 65536, or 262144 bytes), base64-encoded on the wire. Every route
here is served by FastAPI.

All paths are under `/api/v1`, and every one requires `Authorization: Bearer <access
token>` with `full` scope. A full-scope token always names a device, which is the
mailbox drain and ack read. Errors use the envelope and the vocabulary that
[`core/API.md`](../core/API.md) fixes; three responses can appear on any of these
endpoints and are not repeated per section:

- `401 {"code": "unauthenticated", …}` with `WWW-Authenticate: Bearer` when the
  `Authorization` header is absent or malformed;
- `401 {"code": "invalid_token", …}` when the token fails signature, expiry, type or
  claim checks;
- `401 {"code": "token_revoked", …}` when the device is revoked or deleted, a
  generation is stale, or the account has been deactivated.

Every request body rejects a field the endpoint does not declare, and every field is
read strictly: a value of the wrong JSON type is refused rather than converted. All
three endpoints share the `envelopes` throttle scope (default 600/min).

The server never stores who sent an envelope. The sender's identity is used only for
authentication and throttling; each accepted item becomes an independent row keyed
solely by its recipient device.

## Send envelopes

**Method:** `POST`
**Path:** `/api/v1/envelopes`

Accepts a batch of per-device ciphertext copies. The client encrypts the same logical
message separately for every recipient device (including the sender's own other
devices) and submits up to 256 `{device_id, blob}` items. Each accepted item is
queued with a per-device sequence number; live recipients are also pushed a copy over
the WebSocket immediately, but the queue row is the source of truth.

Targets that are revoked, unknown, or belong to a deactivated account are skipped and
reported in `stale_devices`; the sender should drop those devices from its session
state and refresh the peer's device list. The whole batch validates before anything
is written: one off-bucket blob rejects the entire request.

**One call is one transaction.** Every accepted item of a batch is committed together
with the counter advance behind its sequence number, so a retry after an unclear
outcome finds either the whole batch queued or none of it — never a partial batch,
and never a mailbox whose counter ran ahead of its rows.

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
{
  "messages": [
    { "device_id": "2a77d4b9-e611-4c0f-9f1c-6a2e3b7d4e0f", "blob": "kzXhc9Qp…" }
  ]
}
```

1–256 items; each blob exactly one envelope bucket. Unknown fields are rejected.

**Responses**

### Accepted — `202 Accepted`

```json
{ "accepted": 2, "stale_devices": ["b3a91c77-2e5d-4f28-a1c9-8d64e0f3b522"] }
```

### Invalid request — `400 Bad Request`

```json
{ "code": "invalid_request", "detail": { "messages.0.device_id": ["Input should be a valid UUID, invalid character: found `n` at 1"] } }
```

`detail` maps a dotted field path to its messages; a list item carries its index in
that path.

### Off-bucket blob — `400 Bad Request`

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

The rejected payload is never echoed.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "code": "throttled", "detail": "Request was throttled." }
```

## Drain my mailbox

**Method:** `GET`
**Path:** `/api/v1/me/envelopes`

Returns the calling device's queued envelopes in ascending sequence order. `has_more`
signals a further page. Envelopes stay queued until acked, so a crash between drain
and processing loses nothing; clients drain, decrypt, persist locally, then ack.
Undelivered envelopes are pruned after `ENVELOPE_TTL_DAYS` (default **7**), so a
device offline longer than that loses whatever was queued for it.

`pruned_through` is the queue-gap signal that makes that loss detectable: it is the
highest sequence number the TTL prune has ever deleted from this mailbox (0 if
never). **If the device's last acked seq is below `pruned_through`, envelopes were
lost — possibly ratchet messages or group control events, which the server cannot
re-create.** The client must then repair each affected pairwise session through its
authenticated repair path, ask a member for the current group control state, and
surface a recoverable state, never a silent failure (CLIENT_CONTRACT.md §H).

The `limit` parameter is clamped into 1–100 and never errors: a non-numeric value
falls back to 100, a negative one clamps to 1.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, device-bound |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `limit` | integer | no | `100` | Page size, clamped into 1–100 |

**Request body**

None.

**Responses**

### Drained — `200 OK`

```json
{
  "envelopes": [
    { "id": "e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b", "seq": 12, "blob": "kzXhc9Qp…" }
  ],
  "has_more": false,
  "pruned_through": 0
}
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

A register-scope token names no device, so it is refused here on scope; there is no
separate device-binding refusal, because a full-scope token always carries one.

### Rate limited — `429 Too Many Requests`

```json
{ "code": "throttled", "detail": "Request was throttled." }
```

## Acknowledge envelopes

**Method:** `POST`
**Path:** `/api/v1/me/envelopes/ack`

Deletes up to 200 envelopes from the calling device's own queue by id. Ids from any
other mailbox — even a sibling device of the same account — match nothing, and acking
an already-acked id is an idempotent no-op, so retrying after a lost response is
safe. Ack only after the envelope's contents are durably stored client-side.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, device-bound |
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
{ "ids": ["e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b"] }
```

A missing `ids` key acks nothing and returns `{"deleted": 0}`.

**Responses**

### Acked — `200 OK`

```json
{ "deleted": 1 }
```

### Malformed body — `400 Bad Request`

```json
{ "code": "invalid_request", "detail": { "ids.0": ["Input should be a valid UUID, invalid length: expected length 32 for simple format, found 3"] } }
```

Non-object bodies, a non-list `ids`, more than 200 entries, and non-UUID values all
land here; the field path names which one.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "code": "throttled", "detail": "Request was throttled." }
```
