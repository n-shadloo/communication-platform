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
}

/// Capability required to construct the non-production in-memory MLS preview.
final class GroupDevelopmentPreviewPermit {
  const GroupDevelopmentPreviewPermit._();
}
