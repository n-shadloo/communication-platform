import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

/// Piece 06 replaces this with the reviewed, pinned REST client.
/// No public endpoint or alternate origin is contacted in the meantime.
final class PendingHealthReachabilityPort implements HealthReachabilityPort {
  const PendingHealthReachabilityPort();

  @override
  Future<HealthReachabilityResult> check(
    ProvisionedBootstrapConfiguration configuration,
  ) async => const HealthUnreachable();
}
