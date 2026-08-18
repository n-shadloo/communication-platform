# Closed-beta MLS input fuzzing

The harness lives in `src/mls_beta/fuzz.rs` and its submodules. It fuzzes every
decoder an untrusted relay can reach through the closed-beta PQ MLS FFI
operation, and fails on any panic, unbounded allocation, hang, or contained
panic.

## Why the harness is in-crate

`rust-toolchain.toml` pins stable `1.97.1`. `cargo-fuzz`, libFuzzer,
AFL++, ASan, and Miri all require a nightly toolchain, and the project may not
fetch a dependency or a toolchain at build time (`frontend/AGENTS.md`, offline
operation). The harness therefore adds no dependency, needs no toolchain
change, and runs under the ordinary `cargo test` gate. `docs/testing-strategy.md`
records coverage-guided instrumentation and sanitizers as the outstanding gap.

Being in-crate also lets a target call a private decoder directly instead of
only through the ABI, which is what makes the pure-parser targets fast enough
to run millions of inputs.

## Running it

The bounded gate runs automatically and needs no arguments:

```sh
cargo test --locked --all-features
```

A campaign runs in the optimized `fuzz` profile, which keeps
`debug-assertions`, `overflow-checks`, and `panic = "unwind"` on:

```sh
CP_FUZZ_ITERATIONS=100000 cargo test --locked --all-features --profile fuzz \
    mls_beta::fuzz::beta_mls_fuzz_campaign -- --exact --ignored --nocapture
```

`CP_FUZZ_ITERATIONS` is the base budget. A dispatcher target runs that many
inputs; a direct-decoder target runs forty times that many, because one input
costs about a fortieth as much. The printed line reports the exact executed
count, the wall time, and the outcome spread per target.

| variable | default | meaning |
|---|---|---|
| `CP_FUZZ_ITERATIONS` | 25 (gate), 2000 (campaign) | base inputs per target |
| `CP_FUZZ_SEED` | `0x0badc0ded15ea5e5` | mutation schedule root; accepts decimal or the `0x` form findings print |
| `CP_FUZZ_TARGETS` | all | comma-separated target names |
| `CP_FUZZ_MAX_PEAK_BYTES` | 67108864 | allocation-growth ceiling per input |
| `CP_FUZZ_MAX_SINGLE_ALLOC_BYTES` | 16777216 | single-allocation ceiling per input |
| `CP_FUZZ_SLOW_INPUT_MS` | 5000 | slower than this is reported as a hang |
| `CP_FUZZ_WATCHDOG_MS` | 120000 | still running after this aborts the process |
| `CP_FUZZ_ARTIFACTS` | `target/fuzz-artifacts` | where a failing input is written |
| `CP_FUZZ_REPLAY` | none | artifact to replay, for `beta_mls_fuzz_replay` |

## Reproducing a finding

Every finding writes the exact input to `CP_FUZZ_ARTIFACTS` and prints the
command that replays it. The artifact, not the seed, is the unit of
reproduction: the fixtures are real protocol artifacts built with live
randomness, so a given seed replays the same *mutation schedule* but not the
same bytes across processes.

```sh
CP_FUZZ_REPLAY=path/to/artifact.bin CP_FUZZ_TARGETS=<target> \
  cargo test --locked --all-features --profile fuzz \
  mls_beta::fuzz::beta_mls_fuzz_replay -- --exact --ignored --nocapture
```

## Regressions

`regressions/<target>/*.bin` is replayed by
`beta_mls_fuzz_regressions_stay_fixed` on every test run. Only put an input
here when its rejection does not depend on the per-process fixture; anything
else would pass vacuously, because a stale Welcome or `KeyPackage` no longer
matches the freshly keyed fixture. A fixture-dependent defect gets a named
regression test instead, which is why the first campaign's finding is
`every_mls_object_path_refuses_a_non_canonical_encoding` in `fuzz.rs` rather
than a stored artifact.

No generated corpus is committed. The seed corpus is rebuilt from the engine
itself on every run, so it cannot drift away from the wire format.
