# API changes

Every observable change of the client contract since the pre-rebuild state, newest
phase first. The audience is the client developer. Each entry names the route or
field, the old behaviour, the new behaviour, and the client action. The current
contract is `backend/CLIENT_CONTRACT.md` and the per-app `backend/*/API.md`
references; this file records only what moved.

## Phase 1 — group protocol

Groups moved from MLS to pairwise Double Ratchet fan-out
([ADR-0001](docs/architecture/decisions/0001-pairwise-double-ratchet-group-fan-out.md)).
A group session is the set of pairwise sessions between the sender's device and every
member device, each started from the prekey bundles that
`POST /api/v1/users/{user_id}/keys/claim` already serves. The server keeps no group
object, no roster, no epoch, and no group key.

**The server has no counterpart for an MLS profile.** No endpoint accepts, stores, or
serves a key package, a Welcome, a commit, or any other MLS artefact, and none will.
The three routes below, one request field, one bucket set, and one variable are gone,
and `pruned_through` changed meaning.

### Removed routes

Each removed path now falls through the URL resolver. The response is Django's own
`404 Not Found` page (`text/html`), not the JSON error envelope.

| Route | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `PUT /api/v1/me/devices/{device_id}/keypackages` | Stored up to 100 consumable MLS key packages per device, plus one last-resort package, and returned `{"keypackage_count": n}`; `409 {"code": "keypackage_limit"}` at the cap | `404 Not Found` | Delete the upload path. Nothing replaces it: a group start needs no key package |
| `GET /api/v1/me/devices/{device_id}/keypackages/count` | Returned `{"keypackage_count": n}` for the calling device's consumable pool | `404 Not Found` | Delete the poll. Replenish one-time prekeys instead, on `GET /api/v1/me/devices/{device_id}/prekeys/count` (`otpk_count`, `pq_otpk_count`) |
| `POST /api/v1/users/{user_id}/keypackages/claim` | Returned one MLS key package per live device of the user as `{"keypackages": [{"device_id": …, "blob": …}]}`, consuming it, or the device's last-resort package when its pool was empty | `404 Not Found` | Start a group session by claiming PQXDH bundles from `POST /api/v1/users/{user_id}/keys/claim` for each member, exactly as for a direct message (`backend/CLIENT_CONTRACT.md` §F) |

### Removed request field

| Field | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `keypackages` in the body of `POST /api/v1/me/devices` | A required list, empty or up to 100 base64 blobs each padded to a key-package bucket, stored at registration; the client sends `"keypackages": []` | `400 Bad Request` with `{"keypackages": "Unexpected field."}`. The strict serializer rejects the key like any other unknown field, an empty list included | Remove the field from the registration body |

### Removed bucket set and variable

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `KEYPACKAGE_BUCKETS` in `backend/core/buckets.py`, `[4096, 16384]` | The exact padded sizes for key-package blobs; an off-bucket blob was `400 {"code": "bad_bucket"}` | The set no longer exists and no blob type pads to it. Every other bucket set is unchanged | Delete the constant and the padding code that used it |
| `KEYPACKAGE_TTL_DAYS` in the server environment, default 30 | The server deleted consumable key packages older than this many days and kept the last-resort package | The variable no longer exists; there is nothing to rotate | None for the client. The operator removes it from `.env` |

### Changed meaning

| Item | Old behaviour | New behaviour | Client action |
|---|---|---|---|
| `pruned_through` in the response of `GET /api/v1/me/envelopes` | A lost envelope may have been an MLS commit; the device was then permanently desynced from those groups and had to ask peers to remove and re-add it with a fresh Welcome | The shape is unchanged: the highest `seq` the TTL prune has deleted from this mailbox, 0 if never. A lost envelope may have carried a Double Ratchet message or a group control event; the device repairs each affected pairwise session through its authenticated repair path and asks a member for the current group control state | Replace the remove-and-re-add flow with the repair flow (`backend/CLIENT_CONTRACT.md` §H) |

### Unchanged

`POST /api/v1/envelopes` with up to 256 items per call and `accepted` and
`stale_devices` in the response, the envelope queue, `seq`, acknowledgement,
`ENVELOPE_TTL_DAYS`, the device-list `ETag`, the client-signed device log, the
revocation cascade, and the classical and ML-KEM prekey pools with their caps and
counts.
