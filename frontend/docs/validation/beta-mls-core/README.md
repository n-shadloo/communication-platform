# Closed-beta PQ MLS core run records

One directory per measurement run, produced by `tool/measure_beta_mls_core.sh`
and named `YYYY-MM-DD-<model>-<abi>`. These are the evidence the release gate in
`lib/app/config/group_production_gate.dart` reads, and the decision that put the
gate there is [ADR-055](../../decisions.md).

**Gate state: CLOSED. This directory is empty of runs.**
`cp_crypto_v1_beta_mls_operation` has never been executed on any physical device
or emulator, on any ABI, on any date. No run has failed; none has been made. The
group surface is withheld from the distributed artifact for exactly that reason.

## What the measurement answers, and what it does not

It answers one question: **does the packaged closed-beta MLS core compute
correctly on this CPU?** It runs the crate's own `--features beta-pq-mls` test
suite, cross-compiled by the pinned toolchain for one Android ABI, on the
device itself. That covers the ML-KEM, AEAD, signature and ratchet-tree
arithmetic where an ABI-specific `aws-lc` assembly path is selected — the part
that host tests on an x86 workstation cannot speak to.

It does **not** answer whether groups work between people. Multi-device
execution against a live backend, the physical-device crash matrix, and the
remaining piece-19 cells in [`../../mls-profile.md`](../../mls-profile.md) are
separate and stay open. Opening this gate offers the surface; it does not close
gate 6, and it never touches the seven production gates.

## What a run directory holds

| File | What it is |
|---|---|
| `run.json` | the device's own build identity, the toolchain, and the test result |
| `test-output.txt` | the suite's own output, as the device produced it |

## What must never appear in one

The suite runs on generated material and touches no account, no backend and no
user state, so a record has nothing to redact. If a run record ever contains a
message, a username, a token, a key, a server host or an IP address, that is a
defect in the harness rather than a file to edit by hand.

## Admissibility

A record opens a cell only if the gate's own rule accepts it — not emulated, a
strict `YYYY-MM-DD` date, a committed run record path, and every operation of
the round trip exercised. An emulator record may be committed and will never
open anything: an emulator on an x86 host does not run the ARM assembly that is
the entire subject of the measurement. A partially satisfied matrix opens
nothing, because one APK carries every ABI and the installer, not this project,
decides which library a recipient loads.
