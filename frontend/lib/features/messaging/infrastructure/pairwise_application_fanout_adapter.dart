import 'dart:typed_data';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';

final class PairwiseApplicationFanoutAdapter implements ApplicationFanoutPort {
  const PairwiseApplicationFanoutAdapter(this.delegate);

  final PairwiseFanoutCoordinator delegate;

  @override
  Future<Result<ApplicationFanoutOutcome>> prepareAndQueue({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedPayload,
    required ApplicationEventCommit applicationEvent,
  }) async {
    final result = await delegate.prepareAndQueue(
      operationId: operationId,
      eventId: eventId,
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: peerUserId,
      openedOpaquePayload: openedPayload,
      applicationEvent: applicationEvent,
    );
    return result.fold(
      onSuccess: (operation) => Result.success(
        ApplicationFanoutOutcome(targetCount: operation.targets.length),
      ),
      onFailure: Result.failure,
    );
  }
}
