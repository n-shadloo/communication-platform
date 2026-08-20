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
  static GroupPrivateExperimentalPermit? privateExperimentalPermit(
    AppEnvironment environment,
  ) => environment == AppEnvironment.beta
      ? const GroupPrivateExperimentalPermit._()
      : null;
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
