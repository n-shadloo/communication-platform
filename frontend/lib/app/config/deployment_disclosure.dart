import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';

/// The maturity of one user-facing surface, relative to the maturity the whole
/// application declares.
///
/// There is deliberately no value meaning "more mature than the application
/// label". An unlabelled surface is covered by that label and by nothing
/// stronger; a badge reading "supported", "stable", "verified" or "audited"
/// would be a claim nobody outside the project has assessed. Every value here
/// therefore reads *down* from the application label, never up (ADR-045).
enum SurfaceMaturity {
  /// The surface really transmits and really encrypts, using a maintained
  /// implementation, but its cryptography is neither reviewed nor standardised
  /// and the state it produces is disposable by decision (ADR-036, ADR-040).
  experimental,

  /// The surface is routed and visible but has no implementation behind it.
  /// Nothing it appears to offer happens.
  notBuilt;

  String label(AppLocalizations l10n) => switch (this) {
    SurfaceMaturity.experimental => l10n.maturityExperimentalLabel,
    SurfaceMaturity.notBuilt => l10n.maturityNotBuiltLabel,
  };
}

/// One fact about a distributed artifact that a recipient's ordinary
/// expectations of a chat application would otherwise get wrong.
///
/// The set is deliberately short and deliberately free of cryptographic
/// detail. Ciphersuite identifiers, draft revisions and registry state are true
/// but unusable by a reader, and surrounding these seven consequences with them
/// would hide them (ADR-045).
enum DisclosurePoint {
  /// Nothing here has been assessed by anyone outside the project. ADR-017 is
  /// open for every layer, pairwise included.
  noIndependentReview,

  /// Delivery is immediate while the application is open and *best effort*
  /// otherwise: a deferred platform job at the fifteen-minute floor, deferred
  /// further by Doze, and stopped outright by the *rare* and *restricted*
  /// standby buckets, by a force-stop, and by a battery-restricted app. Revised
  /// at revision 2 when alerts arrived (ADR-048), at revision 3 when background
  /// catch-up did (ADR-049), and at revision 4 when the opt-in sustained
  /// delivery capability did (ADR-051) — because a recipient deciding what this
  /// build is good for is deciding it without a material fact if they are not
  /// told that a better tier exists, what it costs them, and that it is still
  /// not guaranteed.
  bestEffortDelivery,

  /// The server stores no history, `allowBackup` is false and the database key
  /// is a non-exportable AndroidKeyStore key, so erasing app data is final.
  deviceOnlyHistory,

  /// The recovery backup carries cross-signing identity material only
  /// (ADR-030); history transfers device-to-device or not at all (ADR-028).
  recoveryExcludesHistory,

  /// Closed-beta PQ MLS group state is disposable by decision and is
  /// reinitialised rather than migrated (ADR-036).
  experimentalGroups,

  /// Surfaces that are routed and visible but not implemented.
  unbuiltSurfaces,

  /// Who this artifact is for, and who it is not for.
  intendedUse;

  String text(AppLocalizations l10n) => switch (this) {
    DisclosurePoint.noIndependentReview => l10n.disclosureNoIndependentReview,
    DisclosurePoint.bestEffortDelivery => l10n.disclosureBestEffortDelivery,
    DisclosurePoint.deviceOnlyHistory => l10n.disclosureDeviceOnlyHistory,
    DisclosurePoint.recoveryExcludesHistory =>
      l10n.disclosureRecoveryExcludesHistory,
    DisclosurePoint.experimentalGroups => l10n.disclosureExperimentalGroups,
    DisclosurePoint.unbuiltSurfaces => l10n.disclosureUnbuiltSurfaces,
    DisclosurePoint.intendedUse => l10n.disclosureIntendedUse,
  };
}

/// What a distributed build tells its recipients about itself, and the revision
/// of that statement.
///
/// The acknowledgement this drives is shown once, as the last step of device
/// enrollment, and is never repeated on a timer: repetition of an unchanged
/// warning measurably destroys it, and the damage generalises to the app's
/// other blocking security states. [revision] therefore exists to make
/// re-acknowledgement *content-triggered* — when what the build promises
/// changes, the revision changes, every later enrollment reads the new text,
/// and re-delivering the written handover disclosure to existing recipients
/// becomes release-blocking (ADR-045).
final class DeploymentDisclosure {
  const DeploymentDisclosure._({required this.revision, required this.points});

  /// The statement carried by the Private Experimental artifact (ADR-044).
  static const privateExperimental = DeploymentDisclosure._(
    revision: 4,
    points: [
      DisclosurePoint.noIndependentReview,
      DisclosurePoint.bestEffortDelivery,
      DisclosurePoint.deviceOnlyHistory,
      DisclosurePoint.recoveryExcludesHistory,
      DisclosurePoint.experimentalGroups,
      DisclosurePoint.unbuiltSurfaces,
      DisclosurePoint.intendedUse,
    ],
  );

  /// Moves when, and only when, the text of any point or the composition of
  /// [points] moves. Asserted by `test/architecture/deployment_disclosure_test.dart`.
  final int revision;

  /// Ordered by consequence: the reader is freshest at the top.
  final List<DisclosurePoint> points;

  String title(AppLocalizations l10n) => l10n.disclosureBuildTitle;
}

/// Which builds carry a deployment disclosure, and which carry none.
///
/// Only a build that is handed to someone else needs to state what it is.
/// Production is unsigned and cannot be installed at all (ADR-042), and the
/// development flavor is never distributed and already names itself in its own
/// banner; neither of them may render the Private Experimental text, so the
/// wording of one build can never leak into the other.
extension AppDeploymentDisclosure on AppEnvironment {
  DeploymentDisclosure? get deploymentDisclosure => switch (this) {
    AppEnvironment.beta => DeploymentDisclosure.privateExperimental,
    AppEnvironment.development || AppEnvironment.production => null,
  };
}
