import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

/// Piece 05 replaces this with Keystore/WebCrypto-backed discovery.
/// It prevents a provisioned production build from pretending protected storage exists.
final class PendingProtectedStoragePort
    implements ProtectedStorageBootstrapPort {
  const PendingProtectedStoragePort();

  @override
  Future<ProtectedStorageAvailability> checkAvailability() async =>
      ProtectedStorageAvailability.unavailable;

  @override
  Future<LocalStateDiscoveryResult> discoverLocalState() async =>
      const LocalStateDiscoveryUnavailable();
}

/// Piece 06 replaces this with the reviewed, pinned REST client.
/// No public endpoint or alternate origin is contacted in the meantime.
final class PendingHealthReachabilityPort implements HealthReachabilityPort {
  const PendingHealthReachabilityPort();

  @override
  Future<HealthReachabilityResult> check(
    ProvisionedBootstrapConfiguration configuration,
  ) async => const HealthUnreachable();
}
