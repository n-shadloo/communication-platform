# vault API

The owner's encrypted storage: a single recovery key backup and an append-only
encrypted history log, both strictly scoped to the calling account. All paths are
under `/api/v1`, JSON in and out with base64 blobs, `Authorization: Bearer` with
`full` scope required throughout (a register-scope token gets
`403 {"code": "scope_forbidden", …}` everywhere). Serializer validation failures
return the DRF field-error object directly (no `code` key); the project-wide `401`
bodies listed in `accounts/API.md` apply here too. The server can never decrypt any
of these blobs, and no endpoint accepts or verifies a recovery secret.

## Read or write the key backup

**Method:** `GET`, `PUT`
**Path:** `/api/v1/me/keybackup`

One backup blob per account, encrypted client-side under the recovery secret. `GET`
returns it; `PUT` replaces it, requiring the blob to be exactly one backup bucket
(4096 to 1048576 bytes) and the version to be strictly greater than the stored one.
A wrong recovery secret fails only on the client; the server offers no check.

A new device calls `GET` after login and decrypts locally. Writers bump `version` on
every upload; on `409` the device refetches, merges, and retries, so a stale device
can never clobber a newer backup — including two racing first uploads.

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
{ "blob": "S0tLS0tLS0tL…", "version": 5 }
```

**Responses**

### Read — `200 OK` (GET)

```json
{ "blob": "S0tLS0tLS0tL…", "version": 5 }
```

### Written — `200 OK` (PUT)

Empty body.

### No backup yet — `404 Not Found` (GET)

```json
{ "code": "not_found" }
```

### Invalid request — `400 Bad Request` (PUT)

```json
{ "version": ["This field is required."] }
```

### Off-bucket blob — `400 Bad Request` (PUT)

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

### Stale version — `409 Conflict` (PUT)

```json
{ "code": "stale_version" }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Read or append history

**Method:** `GET`, `POST`
**Path:** `/api/v1/me/history`

The caller's encrypted history log. `POST` appends up to 100 records per batch; the
server assigns each a per-owner sequence number, contiguous and gapless across
batches and concurrent writers, starting at 0. `GET` pages the log with a keyset
cursor: `?after=<seq>&limit=<n>` returns records with `seq > after` in ascending
order and an honest `has_more`.

A restoring device loops `GET` with `after` set to the last `seq` it received until
`has_more` is false. Bad query values never error: a non-numeric `after` reads from
the start, and a bad or oversized `limit` clamps into 1–500.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | POST only | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters** (GET)

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| `after` | integer | no | `-1` | Return records with `seq` strictly greater than this |
| `limit` | integer | no | `500` | Page size, clamped into 1–500 |

**Request body** (POST)

```json
{ "records": [ { "blob": "aGlzdG9yeS1yZWNvcmQ…" } ] }
```

1–100 records, each blob exactly one envelope bucket (1024–262144 bytes).

**Responses**

### Page — `200 OK` (GET)

```json
{
  "records": [ { "seq": 0, "blob": "aGlzdG9yeS1yZWNvcmQ…" } ],
  "has_more": false
}
```

### Appended — `201 Created` (POST)

```json
{ "first_seq": 250, "last_seq": 262 }
```

### Invalid request — `400 Bad Request` (POST)

```json
{ "records": ["Ensure this field has at least 1 elements."] }
```

### Off-bucket record — `400 Bad Request` (POST)

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Delete history

**Method:** `POST`
**Path:** `/api/v1/me/history/delete`

Deletes history records from the caller's own log: either an explicit list of
sequence numbers (≤ 1000 per call) or everything via `{"all": true}`. Sequence
numbers belonging to other accounts match nothing, and deleting already-deleted
records is an idempotent `{"deleted": 0}`. Remaining sequence numbers keep their
values; deletion leaves gaps, which readers must tolerate.

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
{ "seqs": [1, 3, 7] }
```

or

```json
{ "all": true }
```

**Responses**

### Deleted — `200 OK`

```json
{ "deleted": 3 }
```

### Malformed body — `400 Bad Request`

```json
{ "code": "bad_request" }
```

Non-object bodies, a non-list `seqs`, more than 1000 entries, and non-integer values
all land here.

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## History usage

**Method:** `GET`
**Path:** `/api/v1/me/history/usage`

Reports the record count and total stored bytes of the caller's history log, computed
in one database aggregate. Clients use it to drive retention decisions; an empty log
reports zeros.

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

### Usage — `200 OK`

```json
{ "records": 250, "bytes": 1024000 }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.
