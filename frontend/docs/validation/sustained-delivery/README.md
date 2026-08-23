# Sustained-delivery run records

One directory per measurement run, produced by `tool/measure_sustained_delivery.sh`
and named `YYYY-MM-DD-<device>`. These are the evidence the release gate in
`lib/app/config/sustained_delivery_gate.dart` reads, and the criteria they are
judged against are in [`../../sustained-delivery-validation.md`](../../sustained-delivery-validation.md).

**Gate state: CLOSED.** The two directories here are environment probes on
emulators. An emulator record can never open a cell of the matrix — the harness
marks it `"emulated": true` and the gate's admissibility rule refuses it — so
nothing here is evidence about the capability. It is evidence that the
instrument runs.

## What a run directory holds

| File | What it is |
|---|---|
| `probe.json` | the device's own build identity, and which test conditions it will permit |
| `deviceidle.txt` | that device's Doze constants, read rather than assumed |
| `samples.ndjson` | one line per observation: service, socket, Doze, bucket, exemption, freeze |
| `marks.ndjson` | host-timestamped events, so a send can be paired with an arrival |

## What must never appear in one

Message content, conversation, account, username, token, key, notification text,
server host, IP address. The origin under test is reduced to a socket **count**
before anything is written, so these files disclose neither where this
deployment lives nor who is on it. Runs use dedicated test accounts only, never
a real user's device or account. Anything else that turns up in a run record is
a defect in the harness, not a file to redact by hand.
