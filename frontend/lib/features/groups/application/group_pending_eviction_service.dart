import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';

/// The single authorized control mutation this service needs.
///
/// `MutateGroup.call` satisfies it, which keeps the eviction policy independent
/// of the rest of the group use cases.
typedef GroupControlMutation =
    Future<Result<GroupState>> Function({
      required String groupId,
      required String actorUserId,
      required String actorDeviceId,
      required GroupControlOperation operation,
    });

/// Completes the second half of a leave.
///
/// RFC 9420 section 12.4 forbids a Commit that removes its own committer, so a
/// departing member can only announce the leave. Until a remaining member
/// commits the matching `Remove`, the departed leaf is still in the ratchet
/// tree and still holds the current epoch secret, so the eviction is a
/// security obligation rather than bookkeeping.
///
/// The active owner is the deterministic committer: [GroupAuthorization.canLeave]
/// only lets an owner leave when it is the last active member, so every group
/// that still has other members also still has exactly one active owner. Any
/// other member deliberately does nothing, which keeps concurrent eviction
/// commits — and the fork they would cause — off the wire.
final class GroupPendingEvictionService {
  const GroupPendingEvictionService({
    required this.repository,
    required this.mutate,
    required this.currentUserId,
    required this.currentDeviceId,
  });

  final GroupRepositoryPort repository;
  final GroupControlMutation mutate;
  final String currentUserId;
  final String currentDeviceId;

  /// Evicts at most one departed member per group per pass. The remaining
  /// members are picked up by the next drain, so a partially applied sweep is
  /// always resumable and never leaves a half-written epoch behind.
  Future<Result<int>> evictDepartedMembers({int limit = 20}) async {
    final pendingResult = await repository.readGroupsPendingEviction(
      limit: limit,
    );
    if (pendingResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final pending = (pendingResult as Success<List<GroupState>>).value;
    final localUserId = currentUserId.toLowerCase();
    var evicted = 0;
    for (final group in pending) {
      final actor = group.member(localUserId);
      if (actor == null ||
          !actor.isActive ||
          actor.role != GroupRole.owner ||
          !actor.deviceIds.contains(currentDeviceId.toLowerCase())) {
        continue;
      }
      final departed =
          group.members
              .where(
                (member) =>
                    member.membership == GroupMembershipState.left &&
                    GroupAuthorization.canRemove(
                      group,
                      actorUserId: localUserId,
                      targetUserId: member.userId,
                    ),
              )
              .map((member) => member.userId.toLowerCase())
              .toList(growable: false)
            ..sort();
      if (departed.isEmpty) continue;
      final result = await mutate(
        groupId: group.groupId,
        actorUserId: localUserId,
        actorDeviceId: currentDeviceId.toLowerCase(),
        operation: RemoveGroupMemberOperation(departed.first),
      );
      if (result case FailureResult(failure: final failure)) {
        // A conflicting concurrent control means another commit already
        // advanced this group; the next drain re-reads and retries.
        if (failure is ValidationFailure &&
            failure.kind == ValidationFailureKind.conflict) {
          continue;
        }
        return Result.failure(failure);
      }
      evicted += 1;
    }
    return Result.success(evicted);
  }
}
