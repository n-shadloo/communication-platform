import 'package:communication_platform/app/config/app_environment.dart';
import 'package:flutter/foundation.dart';

/// Compile-time release gate for the unassigned PQ MLS profile.
///
/// There is intentionally no environment define, remote value, or runtime setter.
/// Reopening production groups requires editing this source after the piece-19 review.
final class GroupProductionGate {
  const GroupProductionGate._({required this.productionTransportEnabled})
    : assert(
        !productionTransportEnabled,
        'PQ MLS production transport must remain closed until piece 19 gates pass.',
      );

  static const releaseAssertion = GroupProductionGate._(
    productionTransportEnabled: false,
  );

  final bool productionTransportEnabled;

  static GroupDevelopmentPreviewPermit? developmentPreviewPermit(
    AppEnvironment environment,
  ) => !kReleaseMode && environment == AppEnvironment.development
      ? const GroupDevelopmentPreviewPermit._()
      : null;

  /// The source-only permit ADR-036 requires before the closed-beta PQ MLS
  /// stack may run, and ADR-044 requires before its screens may be reached.
  ///
  /// The beta flavor is a release build, so this deliberately does not test
  /// `kReleaseMode`. It tests the compiled environment instead, which is fixed
  /// by the entry point and cannot be selected at runtime. Production and
  /// development never receive one: production resolves the unsupported
  /// adapter, and only the beta artifact packages a native core exporting
  /// `cp_crypto_v1_beta_mls_operation`.
  ///
  /// Since ADR-055 the environment is necessary and no longer sufficient. The
  /// artifact must also carry field evidence that the packaged core it would
  /// call has been observed executing on real hardware — see
  /// [GroupExperimentalGate].
  ///
  /// ADR-056 made that question per-ABI rather than per-artifact. One APK
  /// carries three native libraries and the installer picks one, so "has the
  /// packaged core been observed running" has three different answers on three
  /// different phones and only [abi] says which one applies here. A device
  /// whose ABI carries an admissible record gets the surface; a device whose
  /// ABI does not is withheld, on the same evidence rule, without any cell
  /// having to be argued away.
  static GroupPrivateExperimentalPermit? privateExperimentalPermit(
    AppEnvironment environment,
    GroupMlsFieldCell? abi,
  ) =>
      environment == AppEnvironment.beta &&
          GroupExperimentalGate.ledger.hasEvidenceFor(abi)
      ? const GroupPrivateExperimentalPermit._()
      : null;

  /// Whether this is the artifact the group surface belongs to, held closed on
  /// this device for want of evidence rather than absent by design.
  ///
  /// Production is never this: it has no group stack to withhold, its packaged
  /// core does not export the symbol, and it says so in different words. The
  /// distinction exists so the interface can be honest about which of the two
  /// a reader is looking at, and it lives here so that the environment
  /// comparison stays in one file (ADR-044) rather than being restated in a
  /// composition root or on a screen.
  static bool privateExperimentalWithheld(
    AppEnvironment environment,
    GroupMlsFieldCell? abi,
  ) =>
      environment == AppEnvironment.beta &&
      !GroupExperimentalGate.ledger.hasEvidenceFor(abi);
}

/// Capability required to construct the non-production in-memory MLS preview.
final class GroupDevelopmentPreviewPermit {
  const GroupDevelopmentPreviewPermit._();
}

/// Capability required to construct the closed-beta PQ MLS stack, upload its
/// KeyPackages, and expose its screens.
///
/// Holding one is never a claim that the suite is standardized, conformant, or
/// reviewed. It marks the one artifact whose group state is disposable by
/// decision (ADR-036) and whose users are told so (ADR-044).
final class GroupPrivateExperimentalPermit {
  const GroupPrivateExperimentalPermit._();
}

/// The release gate ADR-055 puts in front of the closed-beta group surface: the
/// stack may not be offered to a user until the native core it calls has been
/// observed running on the kind of hardware that user has.
///
/// ## Why this exists
///
/// Every other tier of this application is exercised on-device by the artifact
/// that ships it. The closed-beta group stack is not, and the gap is specific
/// rather than general. `cp_crypto_v1_beta_mls_operation` exists only in the
/// `beta` Cargo profile, and that profile is the only one that links
/// `aws-lc-sys` — a C and assembly library, cross-compiled per ABI — and
/// `mls-rs` on top of it. The Dart logic above it, the Rust logic inside it and
/// the exported symbol set of the built library are all evidenced. Whether the
/// thing executes on an ARM phone is evidenced nowhere: no test in this
/// repository calls that symbol on a device or an emulator, and
/// `integration_test/crypto_core_android_smoke_test.dart` covered only the
/// fifteen foundation symbols until ADR-055 extended it.
///
/// A Rust panic inside the operation is contained — the C ABI wraps every call
/// in `catch_unwind` and the release profile keeps `panic = "unwind"` so it
/// can. A fault below Rust in `aws-lc`'s own assembly is not contained by
/// anything, and it takes the process down with the direct-message tier that
/// shares it.
///
/// ## What kind of gate this is
///
/// The same kind as [SustainedDeliveryGate] in
/// `lib/app/config/sustained_delivery_gate.dart`, deliberately: no environment
/// define, no remote value, no runtime setter, no debug override. Opening it
/// for an ABI means editing this file to add a [GroupMlsFieldEvidence] for that
/// [GroupMlsFieldCell], and each record has to survive
/// [GroupMlsFieldEvidence.isAdmissible] — which refuses an emulator, refuses a
/// run that did not exercise the whole local round trip, and refuses a cell
/// that was reasoned about rather than run. An inadmissible record does not
/// open anything; it is simply not counted.
///
/// ## Why it resolves per ABI (ADR-056)
///
/// ADR-055 asked one question of the whole artifact — may it offer groups? —
/// and answered it by requiring every mandatory cell at once. That framing has
/// a defect which only became visible when the first cell was actually
/// measured: `armeabi-v7a` cannot be measured on any hardware this project can
/// obtain, because 64-bit-only ARM devices cannot execute AArch32 at all (the
/// phone the `arm64-v8a` cell was run on reports an empty `abilist32`). Under
/// the old framing the only ways forward were to argue a cell away for being
/// unmeasurable — which is the reason ADR-053 exists to forbid — or to withhold
/// the surface from everybody on account of a device nobody in this deployment
/// is known to have.
///
/// So the question changed rather than the standard. One APK carries three
/// native libraries and the installer picks one, so "has the packaged core been
/// observed running" genuinely has three answers, and the honest gate asks the
/// one that applies to the device in hand. Nothing is demoted, no cell is
/// argued away, and no unmeasured ABI is ever offered the surface. A partially
/// satisfied ledger now opens exactly the part that is satisfied — which is
/// stricter than ADR-055 where it mattered, not looser: under ADR-055 a full
/// ledger would have opened every ABI including any later one added without a
/// run.
///
/// The procedure and the current results are in `docs/mls-profile.md`; the run
/// records are under `docs/validation/beta-mls-core/`.
/// `test/architecture/group_experimental_gate_test.dart` fails if this gate
/// opens without them.
final class GroupExperimentalGate {
  const GroupExperimentalGate._({required this.evidence});

  /// The one instance the application reads.
  ///
  /// `arm64-v8a` was measured on 2026-08-24 and carries an admissible record.
  /// `armeabi-v7a` and `x86_64` carry none and are therefore withheld on the
  /// devices that load them — see ADR-056 and
  /// `docs/validation/beta-mls-core/`.
  static const ledger = GroupExperimentalGate._(
    evidence: <GroupMlsFieldEvidence>[
      GroupMlsFieldEvidence(
        cell: GroupMlsFieldCell.arm64V8a,
        hardware: 'samsung SM-A566B',
        platformVersion: 'Android 16 (API 36), user build',
        observedOn: '2026-08-24',
        emulated: false,
        operations: GroupMlsExercisedOperation.values,
        runRecord:
            'docs/validation/beta-mls-core/2026-08-24-sm-a566b-arm64-v8a/'
            'run.json',
      ),
    ],
  );

  /// Every field measurement recorded for the packaged core, in the order it
  /// was obtained.
  final List<GroupMlsFieldEvidence> evidence;

  /// A gate over a hypothetical ledger, so that a test can prove the mechanism
  /// on ABIs the real ledger has no record for — that a full set really would
  /// open them, and that production stays closed even then.
  ///
  /// The application never calls this. It reads [ledger] and nothing else, so
  /// no build can be handed a ledger at runtime.
  @visibleForTesting
  static GroupExperimentalGate forEvidence(
    List<GroupMlsFieldEvidence> evidence,
  ) => GroupExperimentalGate._(evidence: evidence);

  /// The admissible record for [cell], or null when that cell has none.
  GroupMlsFieldEvidence? evidenceFor(GroupMlsFieldCell cell) {
    for (final record in evidence) {
      if (record.cell == cell && record.isAdmissible) {
        return record;
      }
    }
    return null;
  }

  /// Whether the library this process actually loaded has an admissible record.
  ///
  /// Fails closed twice over: a null [cell] — an ABI this artifact packages no
  /// library for, a desktop host running the test suite, the web target, an
  /// Android RISC-V device, anything added later — has no evidence by
  /// construction, and a cell with only an inadmissible record is treated the
  /// same as a cell with none.
  bool hasEvidenceFor(GroupMlsFieldCell? cell) =>
      cell != null && evidenceFor(cell) != null;

  /// The packaged ABIs that still have no admissible record.
  List<GroupMlsFieldCell> get outstanding => GroupMlsFieldCell.values
      .where((cell) => evidenceFor(cell) == null)
      .toList(growable: false);
}

/// One cell of the packaged-core matrix.
///
/// The axis is the ABI, and only the ABI, because that is what the open
/// question turns on. Whether a manufacturer suspends the process — the axis
/// [SustainedDeliveryFleetCell] uses — does not bear on whether a pure
/// computation returns the right bytes. Which assembly `aws-lc` selects, and
/// how well that path is supported, does: `aws-lc` lists Android `aarch64`
/// among its supported platforms and Android `arm32` under "other platforms",
/// a lower tier, so the 32-bit cell is the more doubtful of the two rather
/// than the more marginal.
enum GroupMlsFieldCell {
  /// 64-bit ARM. Every current phone in this deployment's fleet, and the
  /// library `aws-lc` lists among its supported platforms.
  arm64V8a(abi: 'arm64-v8a'),

  /// 32-bit ARM. Packaged in the same APK, selected by the installer on a
  /// device with no 64-bit support, and built against `aws-lc`'s lower "other
  /// platforms" tier.
  ///
  /// Unmeasured, and not for want of trying: a 64-bit-only ARM device cannot
  /// execute AArch32 at all, so the hardware that measured [arm64V8a] can never
  /// measure this. It stays in the ledger unmeasured rather than being demoted,
  /// and the devices that load it are withheld the surface.
  armeabiV7a(abi: 'armeabi-v7a'),

  /// 64-bit x86. Packaged, but reached in practice only by an emulator, and an
  /// emulated record is never admissible.
  x8664(abi: 'x86_64');

  const GroupMlsFieldCell({required this.abi});

  /// The Android ABI directory name, as the packaged library carries it.
  ///
  /// The mapping from a running process to one of these lives in
  /// `runtime_abi_native.dart`, behind the platform seam, because `dart:ffi`
  /// does not exist on every target this repository still compiles for.
  final String abi;
}

/// One operation of the local round trip a run has to exercise.
///
/// Loading the library and reading its capabilities proves the linker worked.
/// It does not touch `aws-lc`'s ML-KEM, its AEAD, or `mls-rs`'s ratchet tree,
/// which is where the arithmetic that differs per ABI actually lives. A record
/// counts only when every one of these was performed and its output checked.
enum GroupMlsExercisedOperation {
  generateKeyPackages,
  createGroup,
  processWelcome,
  prepareCommit,
  processCommit,
  sendApplicationMessage,
  processApplicationMessage,
}

/// One recorded field measurement: what was run, on what, and when.
///
/// Every field is a fact somebody wrote down after watching a device. There is
/// deliberately no field for a conclusion, a confidence, or an expectation.
final class GroupMlsFieldEvidence {
  const GroupMlsFieldEvidence({
    required this.cell,
    required this.hardware,
    required this.platformVersion,
    required this.observedOn,
    required this.emulated,
    required this.operations,
    required this.runRecord,
  });

  /// Which ABI this record belongs to.
  final GroupMlsFieldCell cell;

  /// The device, as its own build reports it: manufacturer and model.
  final String hardware;

  /// The platform release and API level, as the device reports them.
  final String platformVersion;

  /// The date the run finished, as `YYYY-MM-DD`.
  final String observedOn;

  /// Whether this was an emulator rather than a phone.
  ///
  /// An emulated record is never admissible. It may be recorded — an emulator
  /// answers real questions about the platform — but it cannot stand in for a
  /// cell, because an emulator on an x86 host does not run the ARM assembly
  /// that is the entire subject of this measurement.
  final bool emulated;

  /// Which operations of the round trip were performed and checked.
  final List<GroupMlsExercisedOperation> operations;

  /// The path of the machine-readable run record under
  /// `docs/validation/beta-mls-core/`, relative to `frontend/`.
  final String runRecord;

  /// Whether this record may count towards opening the gate.
  ///
  /// Each clause refuses a specific way a ledger turns into decoration: an
  /// emulator standing in for hardware, a run that loaded the library without
  /// computing anything, and a row with nothing behind it.
  bool get isAdmissible =>
      !emulated &&
      hardware.trim().isNotEmpty &&
      platformVersion.trim().isNotEmpty &&
      _isIsoDate(observedOn) &&
      runRecord.trim().isNotEmpty &&
      GroupMlsExercisedOperation.values.every(operations.contains);

  /// A strict `YYYY-MM-DD`.
  ///
  /// `DateTime.parse` normalises an out-of-range date rather than rejecting it,
  /// so the parsed value is compared back against the digits. A date nobody
  /// could have observed on is not a date this ledger accepts.
  static bool _isIsoDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return false;
    }
    final year = parsed.year.toString().padLeft(4, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$year-$month-$day' == value;
  }
}
