import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';

final class GroupOutboundDispatchReport {
  const GroupOutboundDispatchReport({
    required this.workItems,
    required this.fanoutOperations,
  });

  final int workItems;
  final int fanoutOperations;
}

/// Moves only transactionally persisted MLS work into recipient-bound durable
/// Double Ratchet outboxes. No network call is made here.
final class GroupOutboundDispatcher {
  const GroupOutboundDispatcher({
    required this.repository,
    required this.envelopes,
  });

  final GroupRepositoryPort repository;
  final GroupOutboundEnvelopePort envelopes;

  Future<Result<GroupOutboundDispatchReport>> dispatchPending({
    required String currentUserId,
    required String currentDeviceId,
    int limit = 20,
  }) async {
    final pendingResult = await repository.readPendingOutbound(limit: limit);
    if (pendingResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final pending = (pendingResult as Success<List<GroupOutboundWork>>).value;
    var fanoutOperations = 0;
    for (final work in pending) {
      final recipients = work.recipientUserIds
          .map((value) => value.toLowerCase())
          .toSet();
      final localUser = currentUserId.toLowerCase();
      if (!recipients.contains(localUser)) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.integrityCheckFailed),
        );
      }
      final remoteUsers =
          recipients
              .where((value) => value != localUser)
              .toList(growable: false)
            ..sort();
      final targets = remoteUsers.isEmpty ? <String>[localUser] : remoteUsers;
      for (var index = 0; index < targets.length; index += 1) {
        final target = targets[index];
        final queued = await envelopes.prepareAndQueue(
          operationId: '${work.operationId}:$target',
          eventId: work.eventId,
          currentUserId: localUser,
          currentDeviceId: currentDeviceId.toLowerCase(),
          targetUserId: target,
          openedMlsPayload: work.openedMlsPayload,
          includeOwnDevices: index == 0,
        );
        if (queued case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
        fanoutOperations += 1;
      }
      final routed = await repository.markOutboundRouted(
        operationId: work.operationId,
      );
      if (routed case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
    }
    return Result.success(
      GroupOutboundDispatchReport(
        workItems: pending.length,
        fanoutOperations: fanoutOperations,
      ),
    );
  }
}
