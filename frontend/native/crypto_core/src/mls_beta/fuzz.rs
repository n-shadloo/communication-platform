//! Structure-aware fuzzing of every attacker-reachable closed-beta MLS decoder.
//!
//! The closed beta talks to an untrusted opaque relay, so every byte the relay
//! can influence reaches a decoder here before any signature or AEAD check has
//! succeeded. This harness drives those decoders with mutated real protocol
//! artifacts and fails the build on any panic, unbounded allocation, hang, or
//! contained-panic status.
//!
//! The project cannot use `cargo-fuzz`, libFuzzer, `AFL++`, `ASan`, or Miri:
//! `rust-toolchain.toml` pins stable `1.97.1` and every one of those needs a
//! nightly toolchain, while `frontend/AGENTS.md` requires pinned dependencies
//! and operation without international internet, and `frontend/README.md`
//! requires builds to resolve only from the committed lockfile and an approved
//! local cache. The harness therefore lives in the crate, adds no dependency,
//! needs no toolchain change, and runs under the ordinary `cargo test` gate.
//! `docs/testing-strategy.md` records the missing coverage instrumentation and
//! sanitizers as the outstanding gap.
//!
//! Two entry points share one engine:
//!
//! - `beta_mls_input_boundaries_are_fuzzed` is the bounded regression gate that
//!   runs on every `cargo test --locked --all-features`; and
//! - `beta_mls_fuzz_campaign` is `#[ignore]`d and is the long soak.
//!
//! Both accept `CP_FUZZ_*` overrides, documented on [`Budget`].

use std::{
    collections::{BTreeMap, BTreeSet},
    env, fmt, fs,
    panic::{AssertUnwindSafe, catch_unwind},
    path::{Path, PathBuf},
    sync::{
        Mutex, OnceLock,
        atomic::{AtomicU64, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

mod allocation;
mod corpus;
mod fixture;
mod targets;

use allocation::{AllocationReport, measure};
use corpus::{Corpus, Rng};
use fixture::Fixture;
use targets::{TARGETS, Target};

/// Outcome of one target invocation, used both for reporting and for the
/// deterministic corpus-novelty signal.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct Observation {
    /// Stable `CryptoError` code, or [`Observation::REJECTED`] for a direct
    /// decoder call that returns a module-specific error.
    pub(crate) status: i32,
    /// Bytes the target produced, zero when it produced none.
    pub(crate) produced: usize,
}

impl Observation {
    /// A direct decoder call that rejected its input.
    pub(crate) const REJECTED: i32 = -1;

    pub(crate) const fn accepted(produced: usize) -> Self {
        Self {
            status: 0,
            produced,
        }
    }

    pub(crate) const fn rejected() -> Self {
        Self {
            status: Self::REJECTED,
            produced: 0,
        }
    }

    /// A rejection from a decoder with its own error type. Distinct variants
    /// get distinct negative codes so the corpus keeps one input per rejection
    /// reason, and no code can collide with a contained panic.
    pub(crate) fn rejected_with(variant: u8) -> Self {
        Self {
            status: Self::REJECTED - i32::from(variant),
            produced: 0,
        }
    }

    pub(crate) const fn status(status: i32) -> Self {
        Self {
            status,
            produced: 0,
        }
    }

    /// The deterministic corpus-admission key.
    ///
    /// Only the status code and the magnitude class of the produced length
    /// take part. Both are a pure function of the input, so replaying a seed
    /// replays the exact corpus evolution even though the fixtures themselves
    /// are freshly keyed on every process start.
    fn novelty(self) -> (i32, u32) {
        (self.status, usize::BITS - self.produced.leading_zeros())
    }
}

/// Everything the engine reads from the environment.
#[derive(Clone, Copy, Debug)]
struct Budget {
    /// `CP_FUZZ_ITERATIONS`: inputs executed per target.
    iterations: u64,
    /// `CP_FUZZ_SEED`: root seed for the deterministic mutation schedule.
    seed: u64,
    /// `CP_FUZZ_MAX_PEAK_BYTES`: allocation growth ceiling per input.
    max_peak_bytes: usize,
    /// `CP_FUZZ_MAX_SINGLE_ALLOC_BYTES`: single-allocation ceiling per input.
    max_single_allocation_bytes: usize,
    /// `CP_FUZZ_SLOW_INPUT_MS`: a slower input is reported as a hang.
    slow_input: Duration,
    /// `CP_FUZZ_WATCHDOG_MS`: a still-running input past this aborts the
    /// process, which is the only way to report a non-terminating decoder.
    watchdog: Duration,
}

impl Budget {
    /// Ceilings are deliberately far above any legitimate cost. The largest
    /// accepted input is 1 MiB and the most expensive accepted operation adds
    /// forty-nine hybrid `KeyPackage`s to a group, so anything above these is
    /// driven by an attacker-supplied count or length rather than by the work
    /// the operation actually asked for.
    const DEFAULT_MAX_PEAK_BYTES: usize = 64 * 1024 * 1024;
    const DEFAULT_MAX_SINGLE_ALLOCATION_BYTES: usize = 16 * 1024 * 1024;

    fn resolve(default_iterations: u64) -> Self {
        Self {
            iterations: read_env("CP_FUZZ_ITERATIONS", default_iterations),
            seed: read_seed("CP_FUZZ_SEED", 0x0BAD_C0DE_D15E_A5E5),
            max_peak_bytes: read_env("CP_FUZZ_MAX_PEAK_BYTES", Self::DEFAULT_MAX_PEAK_BYTES),
            max_single_allocation_bytes: read_env(
                "CP_FUZZ_MAX_SINGLE_ALLOC_BYTES",
                Self::DEFAULT_MAX_SINGLE_ALLOCATION_BYTES,
            ),
            slow_input: Duration::from_millis(read_env("CP_FUZZ_SLOW_INPUT_MS", 5_000)),
            watchdog: Duration::from_millis(read_env("CP_FUZZ_WATCHDOG_MS", 120_000)),
        }
    }
}

fn read_env<T: std::str::FromStr>(name: &str, default: T) -> T {
    env::var(name)
        .ok()
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or(default)
}

/// Reads the root seed as decimal or as the `0x` form the harness prints.
///
/// Findings are reported with `{:#018x}`, so that exact text has to be
/// accepted back or the printed reproduction command would silently rerun the
/// default schedule instead of the one that found the defect.
fn read_seed(name: &str, default: u64) -> u64 {
    let Ok(value) = env::var(name) else {
        return default;
    };
    let value = value.trim();
    let parsed = match value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
    {
        Some(hexadecimal) => u64::from_str_radix(hexadecimal, 16),
        None => value.parse(),
    };
    parsed.unwrap_or_else(|_| {
        panic!("{name} must be a decimal or 0x-prefixed 64-bit seed, not {value:?}")
    })
}

/// Why one input is a defect.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Defect {
    Panic,
    ContainedPanic,
    PeakAllocation,
    SingleAllocation,
    Slow,
}

impl fmt::Display for Defect {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Panic => "the decoder panicked",
            Self::ContainedPanic => "the C ABI contained a panic (status 14)",
            Self::PeakAllocation => "allocation growth exceeded the ceiling",
            Self::SingleAllocation => "one allocation exceeded the ceiling",
            Self::Slow => "the input exceeded the slow-input budget",
        })
    }
}

struct Finding {
    defect: Defect,
    target: &'static str,
    iteration: u64,
    seed: u64,
    input: Vec<u8>,
    allocation: AllocationReport,
    elapsed: Duration,
    artifact: Option<PathBuf>,
}

impl fmt::Display for Finding {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        writeln!(
            formatter,
            "{}: {} [target={} seed={:#018x} iteration={} input={} bytes \
             peak={} bytes largest={} bytes elapsed={:?}]",
            self.target,
            self.defect,
            self.target,
            self.seed,
            self.iteration,
            self.input.len(),
            self.allocation.peak_growth,
            self.allocation.largest_single,
            self.elapsed,
        )?;
        match &self.artifact {
            Some(path) => writeln!(
                formatter,
                "  reproduce: CP_FUZZ_REPLAY=\"{}\" CP_FUZZ_TARGETS={} \
                 cargo test --locked --all-features --profile fuzz \
                 mls_beta::fuzz::beta_mls_fuzz_replay -- --exact --ignored --nocapture",
                path.display(),
                self.target,
            ),
            None => writeln!(
                formatter,
                "  the artifact could not be written; the input hex is: {}",
                hex(&self.input),
            ),
        }
    }
}

fn hex(bytes: &[u8]) -> String {
    use std::fmt::Write as _;

    const LIMIT: usize = 512;
    let mut rendered = String::with_capacity(bytes.len().min(LIMIT) * 2 + 16);
    for byte in bytes.iter().take(LIMIT) {
        let _ = write!(rendered, "{byte:02x}");
    }
    if bytes.len() > LIMIT {
        rendered.push_str("… truncated");
    }
    rendered
}

/// Converts a decoder that never returns into a reportable failure.
///
/// Nothing else can: a non-terminating loop inside a target would otherwise
/// hang `cargo test` with no indication of which input caused it.
struct Watchdog {
    deadline: AtomicU64,
    started: Instant,
    label: Mutex<String>,
}

impl Watchdog {
    fn shared() -> &'static Self {
        static WATCHDOG: OnceLock<&'static Watchdog> = OnceLock::new();
        WATCHDOG.get_or_init(|| {
            let watchdog: &'static Watchdog = Box::leak(Box::new(Watchdog {
                deadline: AtomicU64::new(0),
                started: Instant::now(),
                label: Mutex::new(String::new()),
            }));
            thread::Builder::new()
                .name("cp-fuzz-watchdog".to_owned())
                .spawn(|| watchdog.supervise())
                .expect("the fuzz watchdog thread starts");
            watchdog
        })
    }

    fn supervise(&self) -> ! {
        loop {
            thread::sleep(Duration::from_millis(250));
            let deadline = self.deadline.load(Ordering::Acquire);
            if deadline == 0 || self.elapsed_millis() < deadline {
                continue;
            }
            let label = self.label.lock().map_or_else(
                |poisoned| poisoned.into_inner().clone(),
                |label| label.clone(),
            );
            eprintln!("cp-fuzz: watchdog fired, a decoder did not return: {label}");
            std::process::abort();
        }
    }

    fn elapsed_millis(&self) -> u64 {
        u64::try_from(self.started.elapsed().as_millis()).unwrap_or(u64::MAX)
    }

    fn arm(&self, limit: Duration, label: String) {
        if let Ok(mut current) = self.label.lock() {
            *current = label;
        }
        let limit = u64::try_from(limit.as_millis()).unwrap_or(u64::MAX);
        self.deadline.store(
            self.elapsed_millis().saturating_add(limit),
            Ordering::Release,
        );
    }

    fn disarm(&self) {
        self.deadline.store(0, Ordering::Release);
    }
}

/// Runs one input against one target and classifies the result.
fn execute(
    target: &Target,
    fixture: &Fixture,
    input: &[u8],
    budget: Budget,
    iteration: u64,
) -> Execution {
    let watchdog = Watchdog::shared();
    watchdog.arm(
        budget.watchdog,
        format!(
            "target={} seed={:#018x} iteration={iteration} input={} bytes",
            target.name,
            budget.seed,
            input.len(),
        ),
    );
    let started = Instant::now();
    // `catch_unwind` belongs here and never inside a target, so that a panic
    // becomes a reported defect with its exact input instead of a dead test
    // binary.
    let (outcome, allocation) =
        measure(|| catch_unwind(AssertUnwindSafe(|| (target.run)(fixture, input))));
    let elapsed = started.elapsed();
    watchdog.disarm();

    let contained = crate::error::CryptoError::PanicContained.code();
    let Ok(observation) = outcome else {
        return Execution {
            defect: Some(Defect::Panic),
            observation: Observation::status(contained),
            allocation,
            elapsed,
        };
    };
    let defect = if observation.status == contained {
        Some(Defect::ContainedPanic)
    } else if allocation.largest_single > budget.max_single_allocation_bytes {
        Some(Defect::SingleAllocation)
    } else if allocation.peak_growth > budget.max_peak_bytes {
        Some(Defect::PeakAllocation)
    } else if elapsed > budget.slow_input {
        Some(Defect::Slow)
    } else {
        None
    };
    Execution {
        defect,
        observation,
        allocation,
        elapsed,
    }
}

struct Execution {
    defect: Option<Defect>,
    observation: Observation,
    allocation: AllocationReport,
    elapsed: Duration,
}

fn artifact_root() -> PathBuf {
    env::var("CP_FUZZ_ARTIFACTS").map_or_else(
        |_| {
            Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("target")
                .join("fuzz-artifacts")
        },
        PathBuf::from,
    )
}

fn write_artifact(target: &str, input: &[u8]) -> Option<PathBuf> {
    use crate::provider::CryptoProvider as _;

    let directory = artifact_root().join(target);
    fs::create_dir_all(&directory).ok()?;
    let digest = crate::provider::RustCryptoProvider::default()
        .sha256(input)
        .ok()?;
    let path = directory.join(format!("{}.bin", hex(&digest[..8])));
    fs::write(&path, input).ok()?;
    Some(path)
}

/// What one target's campaign observed.
struct Campaign {
    findings: Vec<Finding>,
    executed: u64,
    /// How many inputs ended at each status, which is the evidence for how
    /// deep the mutations actually reach rather than an assertion about it.
    outcomes: BTreeMap<i32, u64>,
}

impl Campaign {
    /// Renders the outcome spread most-frequent last, so the tail that proves
    /// depth stays visible.
    fn outcome_summary(&self) -> String {
        let mut rendered: Vec<String> = self
            .outcomes
            .iter()
            .map(|(status, count)| format!("{}={count}", status_name(*status)))
            .collect();
        rendered.sort_unstable();
        rendered.join(" ")
    }
}

/// Names the stable ABI status codes; anything else is a decoder-private
/// rejection reason and keeps its numeric identity.
fn status_name(status: i32) -> String {
    match status {
        0 => "ok".to_owned(),
        1 => "invalid-argument".to_owned(),
        2 => "input-too-large".to_owned(),
        3 => "output-too-small".to_owned(),
        4 => "malformed".to_owned(),
        7 => "auth-failed".to_owned(),
        8 => "unsupported-version".to_owned(),
        9 => "unsupported-operation".to_owned(),
        10 => "resource-exhausted".to_owned(),
        12 => "state-violation".to_owned(),
        13 => "internal-failure".to_owned(),
        14 => "panic-contained".to_owned(),
        other => format!("status{other}"),
    }
}

/// One target's campaign.
fn fuzz_target(target: &Target, fixture: &Fixture, budget: Budget) -> Campaign {
    let mut rng = Rng::new(budget.seed ^ target.stream_seed());
    let mut corpus = Corpus::new((target.seeds)(fixture));
    let mut seen: BTreeSet<(i32, u32)> = BTreeSet::new();
    let mut findings = Vec::new();
    let mut outcomes: BTreeMap<i32, u64> = BTreeMap::new();
    let mut executed = 0;

    for iteration in 0..target.iterations(budget.iterations) {
        let input = corpus.next_input(&mut rng);
        let execution = execute(target, fixture, &input, budget, iteration);
        executed += 1;
        *outcomes.entry(execution.observation.status).or_default() += 1;
        if seen.insert(execution.observation.novelty()) {
            corpus.retain(input.clone());
        }
        if let Some(defect) = execution.defect {
            let artifact = write_artifact(target.name, &input);
            findings.push(Finding {
                defect,
                target: target.name,
                iteration,
                seed: budget.seed,
                input,
                allocation: execution.allocation,
                elapsed: execution.elapsed,
                artifact,
            });
            // Stop this target at its first defect. A decoder that already
            // misbehaves produces derived findings that hide the original.
            break;
        }
    }
    Campaign {
        findings,
        executed,
        outcomes,
    }
}

fn selected_targets() -> Vec<&'static Target> {
    let filter = env::var("CP_FUZZ_TARGETS").unwrap_or_default();
    let names: Vec<&str> = filter
        .split(',')
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .collect();
    TARGETS
        .iter()
        .filter(|target| names.is_empty() || names.contains(&target.name))
        .collect()
}

fn report(findings: &[Finding]) -> String {
    findings
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .concat()
}

fn run_campaign(default_iterations: u64) {
    let budget = Budget::resolve(default_iterations);
    let targets = selected_targets();
    assert!(!targets.is_empty(), "CP_FUZZ_TARGETS selected no target");
    let fixture = Fixture::shared();

    let started = Instant::now();
    let mut findings = Vec::new();
    let mut executed = 0;
    for target in &targets {
        let target_started = Instant::now();
        let campaign = fuzz_target(target, fixture, budget);
        println!(
            "cp-fuzz:   {:<22} {:>8} inputs {:>7.1}s  {}",
            target.name,
            campaign.executed,
            target_started.elapsed().as_secs_f64(),
            campaign.outcome_summary(),
        );
        executed += campaign.executed;
        findings.extend(campaign.findings);
    }
    println!(
        "cp-fuzz: {} target(s), {executed} inputs, {:.1}s, seed {:#018x}",
        targets.len(),
        started.elapsed().as_secs_f64(),
        budget.seed,
    );
    assert!(
        findings.is_empty(),
        "fuzzing found {} defect(s):\n{}",
        findings.len(),
        report(&findings),
    );
}

/// The bounded gate. Runs on every `cargo test --locked --all-features`.
///
/// The base budget is sized so the gate stays under half a minute in the
/// unoptimized profile. It is a regression gate, not the campaign: it proves
/// every boundary still refuses mutated input, and
/// `beta_mls_fuzz_regressions_stay_fixed` replays every reproducer a real
/// campaign has produced.
#[test]
fn beta_mls_input_boundaries_are_fuzzed() {
    run_campaign(25);
}

/// The soak, run explicitly and in the `fuzz` profile. See
/// `docs/mls-profile.md` for the recorded campaign command, duration, and
/// iteration count.
#[test]
#[ignore = "long soak; the bounded gate runs by default"]
fn beta_mls_fuzz_campaign() {
    run_campaign(2_000);
}

/// Replays one stored artifact. This is the exact reproduction path printed
/// with every finding.
#[test]
#[ignore = "replays the CP_FUZZ_REPLAY artifact"]
fn beta_mls_fuzz_replay() {
    let path = env::var("CP_FUZZ_REPLAY").expect("CP_FUZZ_REPLAY names the artifact to replay");
    let input = fs::read(&path).expect("the replay artifact is readable");
    let budget = Budget::resolve(1);
    let fixture = Fixture::shared();
    let mut findings = Vec::new();
    for target in selected_targets() {
        let execution = execute(target, fixture, &input, budget, 0);
        println!(
            "cp-fuzz: replay {} status={} produced={} peak={} largest={} elapsed={:?}",
            target.name,
            execution.observation.status,
            execution.observation.produced,
            execution.allocation.peak_growth,
            execution.allocation.largest_single,
            execution.elapsed,
        );
        if let Some(defect) = execution.defect {
            findings.push(Finding {
                defect,
                target: target.name,
                iteration: 0,
                seed: budget.seed,
                input: input.clone(),
                allocation: execution.allocation,
                elapsed: execution.elapsed,
                artifact: Some(PathBuf::from(&path)),
            });
        }
    }
    assert!(
        findings.is_empty(),
        "the replayed artifact still fails:\n{}",
        report(&findings),
    );
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{Budget, Defect, Fixture, Observation, Target, execute, read_seed, targets::Depth};
    use crate::error::CryptoError;

    /// One injected defect: its name, the decoder that reproduces it, and the
    /// class the engine has to report.
    type Control = (
        &'static str,
        fn(&Fixture, &[u8]) -> Observation,
        Option<Defect>,
    );

    fn no_seeds(_: &Fixture) -> Vec<Vec<u8>> {
        Vec::new()
    }

    fn clean(_: &Fixture, input: &[u8]) -> Observation {
        Observation::accepted(input.len())
    }

    fn panicking(_: &Fixture, _: &[u8]) -> Observation {
        panic!("negative control: this panic is expected and is being caught")
    }

    fn contained(_: &Fixture, _: &[u8]) -> Observation {
        Observation::status(CryptoError::PanicContained.code())
    }

    /// One oversized reservation, the shape a hostile length prefix drives.
    fn single_allocation(_: &Fixture, _: &[u8]) -> Observation {
        let buffer = vec![0_u8; 8 * 1024 * 1024];
        Observation::accepted(buffer.len())
    }

    /// Many small reservations held at once, the shape a hostile element count
    /// drives. Each one stays under the single-allocation ceiling.
    fn peak_allocation(_: &Fixture, _: &[u8]) -> Observation {
        let held: Vec<Vec<u8>> = (0..64).map(|_| vec![0_u8; 512 * 1024]).collect();
        Observation::accepted(held.len())
    }

    fn slow(_: &Fixture, _: &[u8]) -> Observation {
        std::thread::sleep(Duration::from_millis(120));
        Observation::accepted(0)
    }

    fn control_budget() -> Budget {
        Budget {
            iterations: 1,
            seed: 1,
            max_peak_bytes: 16 * 1024 * 1024,
            max_single_allocation_bytes: 4 * 1024 * 1024,
            slow_input: Duration::from_millis(40),
            watchdog: Duration::from_mins(2),
        }
    }

    /// Without this, a campaign that reports nothing proves nothing. Each
    /// control reproduces one defect class the beta decoders must not have,
    /// and the engine has to classify it exactly.
    #[test]
    fn every_detector_reports_its_injected_defect() {
        let fixture = Fixture::shared();
        let budget = control_budget();
        let controls: [Control; 6] = [
            ("control_clean", clean, None),
            ("control_panic", panicking, Some(Defect::Panic)),
            ("control_contained", contained, Some(Defect::ContainedPanic)),
            (
                "control_single_allocation",
                single_allocation,
                Some(Defect::SingleAllocation),
            ),
            (
                "control_peak_allocation",
                peak_allocation,
                Some(Defect::PeakAllocation),
            ),
            ("control_slow", slow, Some(Defect::Slow)),
        ];
        for (name, run, expected) in controls {
            let target = Target {
                name,
                depth: Depth::Decoder,
                seeds: no_seeds,
                run,
            };
            assert_eq!(
                execute(&target, fixture, b"negative control input", budget, 0).defect,
                expected,
                "{name} was not classified correctly"
            );
        }
    }

    /// Regression for the defect the first closed-beta campaign found.
    ///
    /// `MlsMessage::from_bytes` ignores anything after the object it decodes,
    /// so `object || trailing` decoded to the same message. `hash_mls_object`
    /// and the `KeyPackage` wrapper already re-serialized and compared;
    /// Welcome processing and incoming-message processing did not, so a relay
    /// could append one byte and still have the object applied while the
    /// SHA-256 digest that binds a group-control event to its Commit no
    /// longer matched. Every relay-reachable MLS object path must now refuse
    /// the second encoding.
    #[test]
    fn every_mls_object_path_refuses_a_non_canonical_encoding() {
        let fixture = Fixture::shared();
        let cases: [(&str, &[u8]); 4] = [
            ("welcome_join", &fixture.welcome),
            ("process_message", &fixture.application_message),
            ("mls_object_hash", &fixture.commit),
            ("key_package_wrapper", &fixture.wrapped_key_package),
        ];
        for (name, exact) in cases {
            let target = super::TARGETS
                .iter()
                .find(|candidate| candidate.name == name)
                .unwrap_or_else(|| panic!("{name} is a fuzz target"));
            assert_eq!(
                (target.run)(fixture, exact).status,
                0,
                "{name} must still accept the exact encoding"
            );
            for trailing in [[0x00_u8].as_slice(), &[0xFF], b"trailing"] {
                let mut extended = exact.to_vec();
                extended.extend_from_slice(trailing);
                assert_ne!(
                    (target.run)(fixture, &extended).status,
                    0,
                    "{name} accepted a non-canonical encoding with {} trailing byte(s)",
                    trailing.len()
                );
            }
        }
    }

    /// A seed that cannot be pasted back from a finding is a seed that cannot
    /// reproduce it.
    #[test]
    fn the_printed_seed_form_round_trips_through_the_environment() {
        let seed = Budget::resolve(1).seed;
        let printed = format!("{seed:#018x}");
        // SAFETY: the crate test binary sets this variable only here, and the
        // fuzz entry points read it before they start any worker.
        unsafe {
            std::env::set_var("CP_FUZZ_SEED_ROUND_TRIP", &printed);
        }
        assert_eq!(read_seed("CP_FUZZ_SEED_ROUND_TRIP", 0), seed);
        assert_eq!(read_seed("CP_FUZZ_SEED_ABSENT_ENTIRELY", 7), 7);
        unsafe {
            std::env::remove_var("CP_FUZZ_SEED_ROUND_TRIP");
        }
    }
}

/// Replays every committed reproducer so a fixed defect stays fixed.
#[test]
fn beta_mls_fuzz_regressions_stay_fixed() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("fuzz")
        .join("regressions");
    let Ok(entries) = fs::read_dir(&root) else {
        return;
    };
    let budget = Budget::resolve(1);
    let fixture = Fixture::shared();
    let mut replayed = 0;
    let mut findings = Vec::new();
    for entry in entries {
        let entry = entry.expect("the regression directory is readable");
        let name = entry.file_name();
        let name = name.to_str().expect("regression directories are UTF-8");
        let target = TARGETS
            .iter()
            .find(|target| target.name == name)
            .unwrap_or_else(|| panic!("regression directory {name} names no fuzz target"));
        for artifact in fs::read_dir(entry.path()).expect("the regression corpus is readable") {
            let artifact = artifact
                .expect("the regression artifact is readable")
                .path();
            let input = fs::read(&artifact).expect("the regression artifact is readable");
            let execution = execute(target, fixture, &input, budget, 0);
            replayed += 1;
            if let Some(defect) = execution.defect {
                findings.push(Finding {
                    defect,
                    target: target.name,
                    iteration: 0,
                    seed: budget.seed,
                    input,
                    allocation: execution.allocation,
                    elapsed: execution.elapsed,
                    artifact: Some(artifact),
                });
            }
        }
    }
    println!("cp-fuzz: replayed {replayed} committed regression artifact(s)");
    assert!(
        findings.is_empty(),
        "a committed regression reproducer failed again:\n{}",
        report(&findings),
    );
}
