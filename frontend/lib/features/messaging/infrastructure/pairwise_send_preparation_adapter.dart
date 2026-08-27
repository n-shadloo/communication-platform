import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

/// Runs the fan-out an echoed send owes, on the delivery cycle's thread.
///
/// Everything here used to happen between the user pressing send and their own
/// message appearing: two authenticated device lookups over HTTPS, a prekey
/// claim when a session had to be started, and one ratchet step per recipient
/// device. None of it is faster now — it simply no longer happens while
/// somebody is waiting for a bubble to appear.
final class PairwiseSendPreparationAdapter implements SendPreparationPort {
  const PairwiseSendPreparationAdapter(
    this.coordinator, {
    this.afterSuccessfulQueue,
  });

  final PairwiseFanoutCoordinator coordinator;

  /// Device-log gossip, which the send path used to await.
  ///
  /// It moved here with the rest of the fan-out rather than being dropped: it
  /// is owed to the peer whenever this device sends to them, and it is a fan-out
  /// of its own, with its own device lookup and its own ratchet steps. A failure
  /// is not the send's failure — the message is sealed and queued by the time
  /// this runs, and gossip is caught up by the next send to the same peer.
  final Future<void> Function(String peerUserId)? afterSuccessfulQueue;

  @override
  Future<Result<void>> prepare(PendingSendPreparation preparation) async {
    final prepared = await coordinator.prepareOwedSend(
      OwedSendPreparation(
        operationId: preparation.operationId,
        eventId: preparation.eventId,
        currentUserId: preparation.localUserId,
        currentDeviceId: preparation.localDeviceId,
        peerUserId: preparation.peerUserId,
      ),
    );
    if (prepared case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      await afterSuccessfulQueue?.call(preparation.peerUserId);
    } on Object {
      // Deliberately swallowed, and deliberately not retried here. Gossip is
      // owed to a peer, not to this message, and reporting it would retire or
      // re-arm a preparation whose ciphertext is already durable.
    }
    return const Result.success(null);
  }
}
