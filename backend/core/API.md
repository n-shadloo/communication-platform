# core API

The core app owns shared plumbing (buckets, the opaque blob field, the error
handler, log scrubbing) and exposes exactly one endpoint: an anonymous health probe.
It is served under `/api/v1` like everything else and returns JSON.

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
| `KEYPACKAGE_BUCKETS` | 4096, 16384 | MLS KeyPackages |
| `DEVICELOG_BUCKETS` | 256, 1024 | device-list log records |
| `BACKUP_BUCKETS` | 4096, 16384, 65536, 262144, 1048576 | key backup |
| `ATTACHMENT_BUCKETS` | 64 KiB … 64 MiB, ×4 ladder | attachments |

`KEYPACKAGE_BUCKETS` changed from `[2048, 8192]` to `[4096, 16384]` when PQ
(ML-KEM-768) MLS ciphersuites landed — a **breaking** change: clients must re-pad
KeyPackages or uploads fail with `bad_bucket`. `ENVELOPE_BUCKETS` deliberately has no
2048 step even though a PQXDH initial message (≈1088-byte ML-KEM ciphertext) lands in
the 4096 bucket: fewer buckets means better length uniformity, and at this scale the
wasted bytes are irrelevant.

## Health check

**Method:** `GET`
**Path:** `/api/v1/health`

A reachability probe for clients (the app checks it on startup) and for the
operator's monitoring. It requires no authentication, reads no state, and reveals
nothing but liveness — no version, build, or component status.

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

There are no other responses; the endpoint has no throttle scope and no error paths
of its own. If the service is down, the request fails at the transport level instead.
