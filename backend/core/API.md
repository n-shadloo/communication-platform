# core API

The core app owns shared plumbing (buckets, the opaque blob field, the error
handler, log scrubbing) and exposes exactly one endpoint: an anonymous health probe.
It is served under `/api/v1` like everything else and returns JSON.

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
