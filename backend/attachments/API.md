# attachments API

The encrypted blob store. A client encrypts a file, pads it to an exact attachment
bucket (65536, 262144, 1048576, 4194304, 16777216, or 67108864 bytes), uploads the
raw bytes, and receives an unguessable capability id. The id, together with the
decryption material, travels to recipients inside end-to-end encrypted messages; the
server keeps no recipient list and no ACL — possession of the id is the access
control. Both paths are under `/api/v1`, require `Authorization: Bearer` with `full`
scope, and share the `attachments` throttle scope (default 60/min). Every error body
is the `{code, detail}` envelope defined in `core/API.md`.

## Upload an attachment

**Method:** `POST`
**Path:** `/api/v1/attachments`

Multipart upload of one already-encrypted, already-padded file under the field name
`blob`. The byte size must equal one attachment bucket exactly; the server checks
nothing else about the content. Uploads count against a per-account quota (default
2 GiB); stored attachments expire after a server-side TTL (default 30 days), so
recipients should fetch promptly.

The body must carry exactly one part, and that part must be a file part named `blob`.
A second part of any kind, a non-file field, or a body that is not multipart is
refused. The body cap of this route is the largest attachment bucket plus 8 KiB of
multipart wrapper (`MULTIPART_OVERHEAD_BYTES`); a larger body is `413
payload_too_large`.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | yes | `multipart/form-data` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| — | | | none |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

Multipart form with a single file part named `blob` containing the padded ciphertext
bytes.

**Responses**

### Stored — `201 Created`

```json
{ "attachment_id": "Xk3vT9qLm2WnPzR8sYb4cJdF6hA1gE5uV7iO0wQtN_M", "size": 65536 }
```

The id is 43 characters of URL-safe base64 (256 random bits).

### Malformed body — `400 Bad Request`

```json
{
  "code": "invalid_request",
  "detail": { "blob": ["Expected one multipart file part named `blob`."] }
}
```

Returned when the body is not multipart, carries no `blob` file part, or carries any
other part beside it.

### Off-bucket size — `400 Bad Request`

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Body above the route cap — `413 Payload Too Large`

```json
{ "code": "payload_too_large", "detail": "Request body is too large." }
```

### Quota exhausted — `413 Payload Too Large`

```json
{ "code": "quota_exceeded", "detail": "Storage quota exhausted." }
```

Branch on `code`: both refusals are `413`. The bytes of a refused upload are not
kept.

### Rate limited — `429 Too Many Requests`

```json
{ "code": "throttled", "detail": "Request was throttled." }
```

`Retry-After` carries the seconds to wait.

## Download an attachment

**Method:** `GET`
**Path:** `/api/v1/attachments/{attachment_id}`

Fetches the stored bytes by capability id. Any authenticated full-scope user with the
id may fetch it; a per-recipient ACL would rebuild the conversation graph the schema
avoids. The server authorizes the request and answers with an empty body plus an
`X-Accel-Redirect` header; nginx then streams the file from an internal location. The
response is marked non-cacheable and non-renderable, since the bytes are ciphertext.

Behind the deployed nginx the client simply receives the bytes. Talking to the
application directly (development), the body is empty and the redirect header is
visible.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `attachment_id` | string | yes | 43-character capability id from the upload response |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Served — `200 OK`

Empty body with:

```
Content-Type: application/octet-stream
Content-Disposition: attachment
Cache-Control: private, no-store
X-Accel-Redirect: /_protected_attachments/Xk/Xk3vT9qLm2WnPzR8sYb4cJdF6hA1gE5uV7iO0wQtN_M
```

nginx replaces the empty body with the file bytes.

### Unknown id — `404 Not Found`

```json
{ "code": "not_found", "detail": "No such attachment." }
```

Also returned after the attachment's TTL pruned it. An id of any shape that names no
row answers this; the id is never parsed or validated beyond the row lookup.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "code": "throttled", "detail": "Request was throttled." }
```
