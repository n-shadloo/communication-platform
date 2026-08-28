import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/group_pending_eviction_service.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _owner = '00000000-0000-0000-0000-000000000001';
const _ownerDevice = '10000000-0000-0000-0000-000000000001';
const _admin = '00000000-0000-0000-0000-000000000002';
const _adminDevice = '10000000-0000-0000-0000-000000000002';
const _leaver = '00000000-0000-0000-0000-000000000003';
const _secondLeaver = '00000000-0000-0000-0000-000000000004';

void main() {
  test('the owner commits the Remove that evicts a departed member', () async {
    final repository = _Repository([
      _state(left: const [_leaver]),
    ]);
    final mutations = <GroupControlOperation>[];
    final service = _service(repository, mutations, _owner, _ownerDevice);

    final result = await service.evictDepartedMembers();

    expect((result as Success<int>).value, 1);
    expect(mutations, hasLength(1));
    expect(
      (mutations.single as RemoveGroupMemberOperation).targetUserId,
      _leaver,
    );
  });

  test('a non-owner never commits an eviction', () async {
    final repository = _Repository([
      _state(left: const [_leaver]),
    ]);
    final mutations = <GroupControlOperation>[];
    final service = _service(repository, mutations, _admin, _adminDevice);

    final result = await service.evictDepartedMembers();

    expect((result as Success<int>).value, 0);
    expect(
      mutations,
      isEmpty,
      reason:
          'a single deterministic committer keeps eviction forks off the wire',
    );
  });

  test('an unknown local device does not act for the owner', () async {
    final repository = _Repository([
      _state(left: const [_leaver]),
    ]);
    final mutations = <GroupControlOperation>[];
    final service = _service(repository, mutations, _owner, _adminDevice);

    await service.evictDepartedMembers();

    expect(mutations, isEmpty);
  });

  test('a group with nobody departed is left alone', () async {
    final repository = _Repository([_state()]);
    final mutations = <GroupControlOperation>[];
    final service = _service(repository, mutations, _owner, _ownerDevice);

    final result = await service.evictDepartedMembers();

    expect((result as Success<int>).value, 0);
    expect(mutations, isEmpty);
  });

  test('one eviction per group per pass stays resumable', () async {
    final repository = _Repository([
      _state(left: const [_leaver, _secondLeaver]),
    ]);
    final mutations = <GroupControlOperation>[];
    final service = _service(repository, mutations, _owner, _ownerDevice);

    await service.evictDepartedMembers();

    expect(mutations, hasLength(1));
    expect(
      (mutations.single as RemoveGroupMemberOperation).targetUserId,
      _leaver,
      reason:
          'lowest sorted departed member first, so passes are deterministic',
    );
  });

  test('a concurrent control conflict is retried, not surfaced', () async {
    final repository = _Repository([
      _state(left: const [_leaver]),
    ]);
    final service = GroupPendingEvictionService(
      repository: repository,
      mutate: _conflictingMutate,
      currentUserId: _owner,
      currentDeviceId: _ownerDevice,
    );

    final result = await service.evictDepartedMembers();

    expect((result as Success<int>).value, 0);
  });

  test('a storage failure is surfaced', () async {
    final service = GroupPendingEvictionService(
      repository: _FailingRepository(),
      mutate: _recordingMutate(<GroupControlOperation>[]),
      currentUserId: _owner,
      currentDeviceId: _ownerDevice,
    );

    expect(await service.evictDepartedMembers(), isA<FailureResult<int>>());
  });
}

GroupPendingEvictionService _service(
  GroupRepositoryPort repository,
  List<GroupControlOperation> mutations,
  String userId,
  String deviceId,
) => GroupPendingEvictionService(
  repository: repository,
  mutate: _recordingMutate(mutations),
  currentUserId: userId,
  currentDeviceId: deviceId,
);

GroupState _state({List<String> left = const []}) => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Eviction'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: [
    GroupMember(
      userId: _owner,
      displayName: 'Owner',
      role: GroupRole.owner,
      deviceIds: const [_ownerDevice],
    ),
    GroupMember(
      userId: _admin,
      displayName: 'Admin',
      role: GroupRole.admin,
      deviceIds: const [_adminDevice],
    ),
    for (final userId in const [_leaver, _secondLeaver])
      GroupMember(
        userId: userId,
        displayName: 'Departed',
        role: GroupRole.member,
        membership: left.contains(userId)
            ? GroupMembershipState.left
            : GroupMembershipState.active,
      ),
  ],
  controlRevision: 1,
  controlStateHash: List.filled(32, '01').join(),
  acceptedEpoch: 1,
);

GroupControlMutation _recordingMutate(List<GroupControlOperation> recorded) =>
    ({
      required String groupId,
      required String actorUserId,
      required String actorDeviceId,
      required GroupControlOperation operation,
    }) async {
      recorded.add(operation);
      return Result.success(_state());
    };

Future<Result<GroupState>> _conflictingMutate({
  required String groupId,
  required String actorUserId,
  required String actorDeviceId,
  required GroupControlOperation operation,
}) async =>
    const Result.failure(ValidationFailure(ValidationFailureKind.conflict));

final class _Repository implements GroupRepositoryPort {
  _Repository(this.groups);

  final List<GroupState> groups;

  @override
  Future<Result<List<GroupState>>> readGroupsPendingEviction({
    int limit = 20,
  }) async => Result.success(
    groups
        .where(
          (group) => group.members.any(
            (member) => member.membership == GroupMembershipState.left,
          ),
        )
        .toList(growable: false),
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _FailingRepository implements GroupRepositoryPort {
  @override
  Future<Result<List<GroupState>>> readGroupsPendingEviction({
    int limit = 20,
  }) async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
