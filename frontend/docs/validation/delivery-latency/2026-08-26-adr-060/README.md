# Direct-message delivery, before and after ADR-060

Taken 2026-08-26 on two devices, both signed in to the private deployment with
the two dedicated test accounts, both talking to each other.

| | Device A | Device B |
|---|---|---|
| Hardware | Samsung SM-A566B, arm64-v8a, Android 16 | Android emulator, x86_64, API 36 |
| Before | `0.1.0+1` build 12, schema 13 | `0.1.0+1` build 12, schema 13 |
| After | `0.1.0+1` build 15, schema 15 | `0.1.0+1` build 15, schema 15 |
| Upgrade | `adb install -r`, frozen signing identity, **never uninstalled** — `firstInstallTime` unchanged across builds 13, 14 and 15 | same |

Device A carries real beta data. `tool/verify_upgrade_continuity.sh` was not run
against it and must not be: it uninstalls the application under test, and the
SQLCipher key is a non-exportable Keystore key behind `allowBackup="false"`.

## Instruments, and what each one can resolve

| Reading | How | Floor |
|---|---|---|
| CPU | `cut -d' ' -f14,15 /proc/<pid>/stat`, delta over 10 s, 100 ticks/s | 1 tick = 0.01 CPU-s |
| Traffic | `/proc/net/dev` `wlan0`, delta over 60–180 s | **device-wide, not per-app** — no per-uid accounting exists on either kernel (`/proc/net/xt_qtaguid/stats` is gone, `dumpsys netstats` reports no per-uid bytes) |
| Queue depths | Settings → About → Diagnostics report | order-of-magnitude buckets by design |
| Message states | `uiautomator dump` polled in a loop, read from `content-desc` | ~2.4 s per sample on device A, and a state can be missed while the timeline scrolls |
| Peer arrival | one host timestamp at the tap, host-timestamped poll of the peer | ~1–2 s, dominated by the peer's own dump |
| Half-closed sockets | `/proc/net/tcp{,6}`, `st == 08`, filtered to the application's uid, with each socket's receive-queue length | exact |

## The table

| Metric | Before | After | Target | Verdict |
|---|---|---|---|---|
| Idle CPU, A | 8.97 CPU-s/10 s (investigation); the stalled build measured 0.14 the same day, sitting out a five-minute reconnect draw | **0.00 CPU-s/10 s** settled | < 0.5 | met |
| Idle CPU, B | **4.37 CPU-s/10 s** | **0.00 CPU-s/10 s** at rest; 0.5–1.0 while the socket is reconnecting | < 0.5 | met at rest |
| Idle traffic, A | ~1,088 KB/min (investigation) | 0.7 KB/min with no session; ~45 KB/min foregrounded | < 20 KB/min | ~24× better, **not certified** — see below |
| Idle traffic, B | 1,157 KB/min (investigation); **52.9 KB/min** measured the same day | 0.6 KB/min with no session; ~27 KB/min foregrounded | < 20 KB/min | ~43× better, **not certified** — see below |
| `pending_inbound`, A | `10-99`, frozen over 9 min | **`0`** | 0 | met |
| `pending_inbound`, B | `100-999`, frozen over 6 min | **`0`** | 0 | met |
| `pending_outbound`, both | `1-9` | **`0`** | — | met |
| `quarantined_input`, both | `0` | `100-999` | > 0 expected | met |
| `conversations`, B | **`0`** while a conversation was on screen | `1-9`, matching the list | matches | met |
| `database_schema` | 13 | 15 | — | both repairs ran in place |
| tap → `sending to server` | 15.05 s / 19.91 s | first observed at **5.4 s** | < 1 s | 3–4× better; below the instrument's floor, see below |
| tap → `accepted by server relay` | 18.18 s / 21.6–22.3 s | **7.9 s** | < 2 s | 2.3–2.7× better; same caveat |
| tap → visible on peer | **never** (> 27 min) | **2.33 s** | < 3 s | met |
| `durably delivered` | **never** | **13.6 s** on the probe, and reached on other messages both ways | reached | met |
| Sockets in `CLOSE_WAIT` | 2, holding **16,456** and **7,546** unread bytes, persisting > 20 min | 0–10, each holding **25–75** bytes | 0 | changed in kind — see below |
| `last_successful_sync_at` | never advanced | advances; `delivery_session=running`, phase settles to online | advances | met |
| The two stranded probes | never delivered | **both delivered**, and a third and fourth sent afterwards delivered too | deliver or be accounted for | met |

## Three readings that need the caveat spelled out

**Idle traffic is device-wide.** Neither kernel offers per-uid byte accounting,
so the foregrounded figures include everything else the device is doing —
and device A is behind a VPN that tunnels its own traffic over the same
interface, counting the application's bytes twice. The bound that *is* per-app:
with no delivery session the whole device moves 0.6–0.7 KB/min, so the
application's share of the foregrounded figure is nearly all of it. The residual
is reconnect churn rather than queue work: with all four queues at zero, stopping
the peer entirely made device B's traffic *rise* (27 → 39 KB/min), which is a
socket dropping and being re-established, not a conversation. Both devices report
`most_failed_operation=websocket` with `backend_rejected=0`, which is the same
transport flakiness the investigation measured and set aside.

**The send-latency instrument cannot resolve the target.** A `uiautomator` dump
costs ~2.4 s on device A, and the first sample after a tap regularly misses the
new bubble while the timeline scrolls, so 5.4 s to `sending to server` is an
upper bound containing at least one full sample period and one scroll. The
figure that does not depend on this instrument is the peer-arrival one, and it
settles the question by implication: a message cannot be visible on the peer
**2.33 seconds** after the tap unless it was encrypted, committed, POSTed,
accepted by the relay, pushed, drained and applied inside that window.

**The half-closed sockets changed in kind, not only in count.** What the
investigation found was two abandoned response bodies — 16,456 and 7,546 bytes
the client had asked for, refused, and then never read — held open for the life
of the process. What remains is a rotating handful of pooled connections each
holding 25 to 75 bytes, which is a TLS `close_notify` from a server that reached
its keep-alive timeout first. Those are reaped and replaced; they are not
responses nobody read.
