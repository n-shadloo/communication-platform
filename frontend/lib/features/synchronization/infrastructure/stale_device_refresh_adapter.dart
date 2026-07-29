import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';

/// Refreshes the authenticated contact projection after a stale-device response.
/// The sync engine never accepts the stale list itself as authorization.
final class ContactStaleDeviceRefreshAdapter implements StaleDeviceRefreshPort {
  const ContactStaleDeviceRefreshAdapter(this.authentication);

  final PeerAuthenticationService authentication;

  @override
  Future<Result<void>> refreshUserDevices(String userId) async {
    final result = await authentication.refreshPeer(
      userId: userId,
      requirePrekeys: false,
    );
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return const Result.success(null);
  }
}
