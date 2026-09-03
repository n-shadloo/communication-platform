# 0001. Groups use pairwise Double Ratchet fan-out

- Status: Accepted
- Phase: 1
- Date: 2026-09-03
- Landed: 2026-09-03, in the second run of phase 1

## Context

The group design in the tree is MLS. `devices.KeyPackage` exists, three
key-package endpoints serve it, and the server is expected to hold a group
object with a roster and an epoch.

That contradicts the threat model. `backend/SECURITY.md` accepts an attacker with
live root access on the VPS: content stays secret, and the social graph does not
have to. A roster is the social graph, written down, at rest, in a table that
survives a seizure. Invariant 3 of this system already forbids a membership
table, and MLS group state is a membership table with cryptography attached.

The scale band decides the rest. A group holds at most 50 members, each with at
most 10 devices. MLS exists because pairwise fan-out becomes expensive as a group
grows; at 50 members that cost has not arrived, and the system pays for it in
ciphertext rather than in server-held state.

## Decision

A group message is one logical event. The sender encrypts it independently for
every live device of every member, and for every other live device of the sender,
with the existing PQXDH plus Double Ratchet session.

The server has no group object, no roster, no epoch, no group key, and no key
package. Group state lives in client-signed control events carried as ordinary
envelopes. Every MLS-only artefact leaves the repository.

## Position fields

- **Forcing function.** An MLS server holds group state, and group state is the
  social graph the threat model refuses to store.
- **Scale band.** Band 0, holding through band 1. The band caps a group at 50
  members and a member at 10 devices.
- **Flip trigger.** A group needs more than approximately 50 members, or the
  per-message fan-out cost dominates send latency. Sender keys, not MLS, are the
  first step past that trigger.
- **Cost.** O(devices) ciphertext for each message. A 50-member group with 10
  devices each costs at most 500 envelope rows for one send. The client, not the
  server, carries group membership, so a client that loses its state loses its
  view of the group.
- **Evidence.** Signal's original private group messaging kept group state on the
  clients and left the server with none; the server saw only pairwise messages.
  The pairwise cost model is exactly why sender keys were later introduced for
  larger groups, which is the same trade this decision makes in the opposite
  direction at a much smaller size. **Currency:** current.

## Consequences

- The server keeps no group state, no roster and no group key. Invariant 10 of
  the rebuild is a direct consequence.
- `devices.KeyPackage`, its three endpoints, its migration state and its tests
  leave in phase 1. `backend/devices/API.md` loses the key-package section.
- Membership becomes a client-side agreement. A client-signed control event
  carried as an ordinary envelope is the only mechanism; the server cannot
  arbitrate a disagreement about who is in a group, and is not meant to.
- A device that is offline when a member is added learns of the change from the
  control event, on the same delivery path as any other envelope.
- Fan-out cost is visible in `messaging.QueuedEnvelope` row counts. That is the
  measurement that will fire the flip trigger; `GROUND-TRUTH.md` holds no row
  count yet.
