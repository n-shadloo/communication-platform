# voicerooms API

Standalone voice rooms. A persistent room is nothing but a capability id and an
encrypted name; membership, invites, roles, and media crypto state are client-side
state carried over the messaging queue, and live participation exists only in
non-persistent Redis. These endpoints create and rename rooms, read a room with its
live count, and mint LiveKit join tokens. All paths are under `/api/v1`, JSON with
base64 blobs, `Authorization: Bearer` with `full` scope required. Serializer
validation failures return the DRF field-error object directly (no `code` key); the
project-wide `401` bodies listed in `accounts/API.md` apply here too.

## Create a room

**Method:** `POST`
**Path:** `/api/v1/rooms`

Creates a room from an encrypted name blob and returns its id. The id is the
capability: anyone who holds it (learned through an encrypted invite) can read,
rename, subscribe, and join voice. There is no owner column and no member table.

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
{ "name_blob": "cm9vbS1uYW1lLXBhZGRlZA…" }
```

Exactly one name bucket (256 or 1024 bytes) after decoding.

**Responses**

### Created — `201 Created`

```json
{ "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f" }
```

### Invalid request — `400 Bad Request`

```json
{ "name_blob": ["This field is required."] }
```

### Off-bucket name — `400 Bad Request`

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

## Read or rename a room

**Method:** `GET`, `PUT`
**Path:** `/api/v1/rooms/{room_id}`

`GET` returns the room's encrypted name, its day-coarse `updated_date`, and the
number of devices currently in the live voice session. `PUT` replaces the name blob
and bumps `updated_date`, which is how peers polling `GET` notice a rename.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope |
| `Content-Type` | PUT only | `application/json` |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `room_id` | UUID | yes | The room capability id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body** (PUT)

```json
{ "name_blob": "bmV3LXJvb20tbmFtZQ…" }
```

**Responses**

### Read — `200 OK` (GET)

```json
{
  "room_id": "7c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f",
  "name_blob": "cm9vbS1uYW1lLXBhZGRlZA…",
  "updated_date": "2026-07-23",
  "live_count": 2
}
```

### Renamed — `200 OK` (PUT)

Empty body.

### Unknown room — `404 Not Found`

`GET` returns `{"code": "not_found"}`; `PUT` returns an empty body.

### Invalid request — `400 Bad Request` (PUT)

```json
{ "name_blob": ["This field is required."] }
```

An off-bucket name is `400 {"code": "bad_bucket", "detail": "Invalid payload."}`.

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `accounts`, default 120/min.

## Mint a voice join token

**Method:** `POST`
**Path:** `/api/v1/rooms/{room_id}/token`

Mints a short-lived LiveKit access token for exactly this room and the calling
device: an audio-only grant (microphone publish, subscribe, no data channel), signed
with the LiveKit API secret. The client connects to the returned LiveKit URL with the
token before it expires. The token carries no media keys; media encryption is
negotiated client-side and the server never joins the media path.

Requires a device-bound token, since the LiveKit identity is the device id. Mint on
join and re-mint on reconnect; tokens default to a 300-second lifetime.

**Headers**

| Header | Required | Value |
|---|---|---|
| `Authorization` | yes | `Bearer <access token>`, full scope, device-bound |

**Path parameters**

| Name | Type | Required | Description |
|---|---|---|---|
| `room_id` | UUID | yes | The room capability id |

**Query parameters**

| Name | Type | Required | Default | Description |
|---|---|---|---|---|
| — | | | | none |

**Request body**

None.

**Responses**

### Minted — `200 OK`

```json
{
  "url": "wss://chat.example.dev/rtc",
  "token": "eyJhbGciOiJIUzI1NiIs…",
  "expires_in": 300
}
```

### No device binding — `403 Forbidden`

```json
{ "code": "device_scope_required" }
```

### Register-scope token — `403 Forbidden`

```json
{ "code": "scope_forbidden", "detail": "This token cannot access this endpoint." }
```

### Unknown room — `404 Not Found`

```json
{ "code": "not_found" }
```

### Voice not configured — `503 Service Unavailable`

```json
{ "code": "voice_unconfigured" }
```

Returned when any of `LIVEKIT_URL`, `LIVEKIT_API_KEY`, or `LIVEKIT_API_SECRET` is
unset.

### Rate limited — `429 Too Many Requests`

```json
{ "detail": "Request was throttled." }
```

Scope `roomtoken`, default 60/min.
