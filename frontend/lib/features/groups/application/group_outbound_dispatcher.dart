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
    Failure? firstFailure;
    for (final work in pending) {
      final routed = await _route(
        work,
        currentUserId: currentUserId.toLowerCase(),
        currentDeviceId: currentDeviceId.toLowerCase(),
        onFanout: () => fanoutOperations += 1,
      );
      // Pending work is ordered by creation, so ending the pass on the first
      // failure would let one operation nobody can route — an unreachable
      // recipient, a corrupt persisted row — strand every later group's
      // durable ciphertext behind it for as long as its cause lasts. Each
      // operation is independent and idempotent, so the rest continue and the
      // first failure is still surfaced to the caller.
      if (routed case FailureResult(failure: final failure)) {
        firstFailure ??= failure;
      }
    }
    return firstFailure != null
        ? Result.failure(firstFailure)
        : Result.success(
            GroupOutboundDispatchReport(
              workItems: pending.length,
              fanoutOperations: fanoutOperations,
            ),
          );
  }

  /// Fans one persisted object out to every recipient, then marks it routed.
  ///
  /// The marker is deliberately last and deliberately separate: a crash
  /// between the two leaves the object pending, and the next pass reuses the
  /// exact ciphertext already persisted for each recipient rather than
  /// advancing any ratchet a second time.
  Future<Result<void>> _route(
    GroupOutboundWork work, {
    required String currentUserId,
    required String currentDeviceId,
    required void Function() onFanout,
  }) async {
    final recipients = work.recipientUserIds
        .map((value) => value.toLowerCase())
        .toSet();
    if (!recipients.contains(currentUserId)) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    final remoteUsers =
        recipients
            .where((value) => value != currentUserId)
            .toList(growable: false)
          ..sort();
    final targets = remoteUsers.isEmpty ? <String>[currentUserId] : remoteUsers;
    for (var index = 0; index < targets.length; index += 1) {
      final target = targets[index];
      final queued = await envelopes.prepareAndQueue(
        operationId: '${work.operationId}:$target',
        // One group object becomes one pairwise operation per recipient user,
        // and a pairwise operation owns its logical send outright: the durable
        // outbox holds at most one local application per event id. The group
        // event id is therefore qualified the same way the operation id is,
        // so a group with two or more remote members can fan out at all.
        // Recipients still deduplicate on the identifiers inside the MLS
        // object, which this does not touch.
        eventId: '${work.eventId}:$target',
        currentUserId: currentUserId,
        currentDeviceId: currentDeviceId,
        targetUserId: target,
        openedMlsPayload: work.openedMlsPayload,
        includeOwnDevices: index == 0,
      );
      if (queued case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      onFanout();
    }
    return repository.markOutboundRouted(operationId: work.operationId);
  }
}
