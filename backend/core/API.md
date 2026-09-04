# core API

The core app owns shared plumbing (buckets, the opaque blob field, log scrubbing) and
exposes exactly one endpoint: an anonymous health probe. It is served under `/api/v1`
like everything else and returns JSON.

## The error envelope

Every error this API returns is

```json
{ "code": "…", "detail": "…" }
```

`detail` is a string, except for `invalid_request`, where it is an object mapping a
field path to the list of messages that failed. No error body ever echoes request
input, and a `500` body carries no traceback.

The vocabulary is fixed. A client branches on `code`, never on `detail`.

| Status | Code | Meaning |
|---|---|---|
| 400 | `invalid_request` | Request validation failed. `detail` maps field paths to messages. |
| 400 | `bad_bucket` | A blob has an off-bucket length. `detail` is `"Invalid payload."`. |
| 400 | `identity_required` | A second device registers before the identity is published. |
| 401 | `unauthenticated` | The `Authorization` header is absent or malformed. `WWW-Authenticate: Bearer` is set. |
| 401 | `invalid_token` | The token fails signature, expiry, type, or claim checks. |
| 401 | `token_revoked` | The device is revoked, a generation is stale, or the account is inactive. |
| 401 | `invalid_credentials` | Login username or password is wrong. |
| 403 | `account_inactive` | Login succeeded but the owner has not activated the account. |
| 403 | `scope_forbidden` | A register-scope token reached a full-scope route. |
| 403 | `device_scope_required` | The route needs a device-bound token. |
| 403 | `forbidden` | The token belongs to another device than the path names. |
| 404 | `not_found` | No such route or resource. |
| 405 | `method_not_allowed` | The route exists; the method does not. `Allow` lists the methods of one route object. |
| 409 | `username_taken` | Registration name conflict, including the concurrent race. |
| 409 | `stale_version` | A version did not increase. |
| 409 | `device_limit` | The account holds `MAX_DEVICES_PER_USER` live devices. |
| 409 | `prekey_limit` | A prekey pool cap is reached. |
| 413 | `payload_too_large` | The body exceeds the route cap. |
| 413 | `quota_exceeded` | The attachment quota is exhausted. |
| 429 | `throttled` | Rate limit reached, or a login name in its cool-off. `Retry-After` carries the seconds to wait. |
| 500 | `server_error` | Unhandled failure. `detail` is `"Internal error."`. |
| 503 | `unavailable` | The rate-limit store is unreachable, or the request exceeded its deadline. |
| 503 | `voice_unconfigured` | LiveKit is not configured. |

One surface serves this API. Every route of every app answers through FastAPI and
uses the envelope everywhere, including for a `404` on a path no route serves and a
`405` on a method a route does not carry. `Allow` on a `405` names the methods of one
route object, so on a path two methods share it names one of them and not both:
branch on `code`, and never read `Allow` as the complete method set of a path.

One code in the table is reserved rather than reachable today.
`device_scope_required` belongs to a route that needs a device-bound token where the
requirement itself does not supply one; every route now takes a requirement that
does, so no route returns it. It stays in the vocabulary.

## What a route's own section does not repeat

Every `API.md` section lists the responses that route produces. Four statuses are not
repeated there, because a route answers them from what it declares rather than from
anything it does:

| Status | Codes | Why every route can answer it |
|---|---|---|
| `401` | `unauthenticated`, `invalid_token`, `token_revoked` | the authentication requirement the route declares, before the handler runs |
| `403` | `scope_forbidden` | the same requirement, on a register-scope token |
| `500` | `server_error` | the unhandled-failure handler, on any route |
| `503` | `unavailable` | the request deadline of `api/middleware.py`, on any route |

A route with no authentication requirement — `GET /api/v1/health`, and the three
`/auth` routes a client reaches before it holds a token — answers neither `401
unauthenticated` nor `403 scope_forbidden` for that reason. Where one of these
statuses carries a code of its own, the route does list it: `403 forbidden` on the
two prekey routes, `503 voice_unconfigured` on the join-token route.

Three refusals belong to no route at all, because the surface answers them before it
has chosen one: `400 invalid_request` for a `Host` that `DJANGO_ALLOWED_HOSTS` does
not list, `404 not_found` for a path no route serves, and `405 method_not_allowed`
for a method a route does not carry.

## The machine-readable form

`backend/openapi.json` is the OpenAPI document of this surface, generated from the
routes by `python manage.py openapi` and checked against them in CI. It carries every
path, every method, every request and response shape, and every status of the table
above. It does not carry what these files exist for: the retry semantics of each
mutating route, the bucket rules, and the WebSocket close codes.

Under `DEBUG` the same document is served at `/openapi.json`, with the interactive
views at `/docs` and `/redoc`. All three are closed outside `DEBUG` — a route map is
reconnaissance on a server whose posture is to reveal nothing — and the two
interactive views load their JavaScript from a public CDN, so the committed artefact
is the reference that works offline.

## Request limits

Every response carries `X-Content-Type-Options: nosniff`, `Cache-Control: no-store`
and `Referrer-Policy: no-referrer`.

A request whose `Host` header is not in `DJANGO_ALLOWED_HOSTS` is refused with
`400 {"code": "invalid_request", "detail": {"host": ["Unknown host."]}}` before any
route sees it. A body above the route's cap is `413 payload_too_large`, counted as the
bytes arrive rather than read from `Content-Length`. A request that outlives its
deadline is `503 unavailable`. The caps and deadlines are operator settings; the
defaults are in `backend/README.md`.

A trailing slash is never redirected: `/api/v1/health/` is a `404`, not a `307`.

## Padding buckets

Every stored ciphertext must decode to exactly one of the sizes for its type
(`core/buckets.py`); anything else is `400 {"code": "bad_bucket"}` without the
payload being echoed. Current sets, in bytes:

| Set | Sizes | Used by |
|---|---|---|
| `ENVELOPE_BUCKETS` | 1024, 4096, 16384, 65536, 262144 | queued envelopes |
| `PROFILE_BUCKETS` | 1024, 4096 | profile blobs |
| `LABEL_BUCKETS` | 256, 1024 | device labels |
| `NAME_BUCKETS` | 256, 1024 | room names |
| `DEVICELOG_BUCKETS` | 256, 1024 | device-list log records |
| `BACKUP_BUCKETS` | 4096, 16384, 65536, 262144, 1048576 | key backup |
| `ATTACHMENT_BUCKETS` | 65536, 262144, 1048576, 4194304, 16777216, 67108864 | attachments |

`ENVELOPE_BUCKETS` deliberately has no 2048 step even though a PQXDH initial message
(≈1088-byte ML-KEM ciphertext) lands in the 4096 bucket: fewer buckets means better
length uniformity, and at this scale the wasted bytes are irrelevant.

## Health check

**Method:** `GET`
**Path:** `/api/v1/health`

A reachability probe for clients (the app checks it on startup) and for the
operator's monitoring. It requires no authentication, reads no state, and reveals
nothing but liveness — no version, build, or component status. It carries no rate
limit, so it still answers while the rate-limit store is down.

**Headers**

| Header | Required | Value |
|---|---|---|
| — | | none required |

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

### Alive — `200 OK`

```json
{ "status": "ok" }
```

There are no other responses of its own. If the service is down, the request fails at
the transport level instead.
