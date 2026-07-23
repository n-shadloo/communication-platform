# attachments API

The encrypted blob store. A client encrypts a file, pads it to an exact attachment
bucket (65536, 262144, 1048576, 4194304, 16777216, or 67108864 bytes), uploads the
raw bytes, and receives an unguessable capability id. The id, together with the
decryption material, travels to recipients inside end-to-end encrypted messages; the
server keeps no recipient list and no ACL — possession of the id is the access
control. Both paths are under `/api/v1`, require `Authorization: Bearer` with `full`
scope, and share the `attachments` throttle scope (default 60/min). The project-wide
`401` bodies listed in `accounts/API.md` apply here too.

## Upload an attachment

**Method:** `POST`
**Path:** `/api/v1/attachments`

Multipart upload of one already-encrypted, already-padded file under the field name
`blob`. The byte size must equal one attachment bucket exactly; the server checks
nothing else about the content. Uploads count against a per-account quota (default
2 GiB); stored attachments expire after a server-side TTL (default 30 days), so
recipients should fetch promptly.

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

### Missing file — `400 Bad Request`

```json
{ "code": "bad_request", "detail": "Expected a single `blob` file." }
```

### Off-bucket size — `400 Bad Request`

```json
{ "code": "bad_bucket", "detail": "Invalid payload." }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Quota exhausted — `413 Payload Too Large`

```json
{ "code": "quota_exceeded", "detail": "Storage quota exhausted." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

## Download an attachment

**Method:** `GET`
**Path:** `/api/v1/attachments/{attachment_id}`

Fetches the stored bytes by capability id. Any authenticated full-scope user with the
id may fetch it; a per-recipient ACL would rebuild the conversation graph the schema
avoids. Django authorizes the request and answers with an empty body plus an
`X-Accel-Redirect` header; nginx then streams the file from an internal location. The
response is marked non-cacheable and non-renderable, since the bytes are ciphertext.

Behind the deployed nginx the client simply receives the bytes. Talking to Daphne
directly (development), the body is empty and the redirect header is visible.

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

Empty Django body with:

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

Also returned after the attachment's TTL pruned it.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```
