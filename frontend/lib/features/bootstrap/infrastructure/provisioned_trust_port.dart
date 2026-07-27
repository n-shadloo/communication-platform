import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

/// Fail-closed validation of the trust material selected for this platform.
///
/// Android handshake enforcement belongs to the native network-security configuration
/// and the reviewed pinned transport adapter. Browser CA trust is external and a TLS
/// failure from the health request is mapped to a blocking trust result by that adapter.
final class ProvisionedTrustPort implements PlatformTrustPort {
  const ProvisionedTrustPort();

  @override
  Future<TrustValidationResult> validate(
    ProvisionedBootstrapConfiguration configuration,
    BootstrapPlatform platform,
  ) async {
    final material = configuration.trustMaterial;
    final matchesPlatform = switch ((platform, material)) {
      (BootstrapPlatform.android, AndroidTrustMaterial()) => true,
      (BootstrapPlatform.web, WebTrustMaterial()) => true,
      _ => false,
    };
    return matchesPlatform
        ? const TrustValidated()
        : const TrustValidationFailed(TrustFailureKind.invalidProvisioning);
  }
}
