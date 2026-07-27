import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

abstract interface class BootstrapConfigurationPort implements Port {
  Future<ConfigurationLoadResult> load();
}

abstract interface class ProtectedStorageBootstrapPort implements Port {
  Future<ProtectedStorageAvailability> checkAvailability();

  Future<LocalStateDiscoveryResult> discoverLocalState();
}

/// Validates that platform trust is provisioned before any request is attempted.
///
/// The eventual native implementation must validate the private CA and accept a
/// certificate only when its SPKI matches the configured primary or backup pin.
/// Web implementations model externally installed OS/browser trust and never bypass it.
abstract interface class PlatformTrustPort implements Port {
  Future<TrustValidationResult> validate(
    ProvisionedBootstrapConfiguration configuration,
    BootstrapPlatform platform,
  );
}

/// Performs only `GET /api/v1/health` against [configuration]'s origin.
abstract interface class HealthReachabilityPort implements Port {
  Future<HealthReachabilityResult> check(
    ProvisionedBootstrapConfiguration configuration,
  );
}
