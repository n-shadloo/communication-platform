import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The peer half of the queue-gap recovery matrix.
///
/// A device that lost envelopes to the backend's seven-day cap cannot repair
/// itself: the missing objects may have been Commits whose epoch secrets are
/// gone. `CLIENT_CONTRACT.md` §H and `sync-engine.md` therefore make removal
/// and re-addition the only recovery, which means the group side must be able
/// to add back a member it has already evicted. These tests pin that
/// transition and the three neighbouring states that must stay refused.
const _groupId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _owner = '00000000-0000-0000-0000-000000000001';
const _admin = '00000000-0000-0000-0000-000000000002';
const _member = '00000000-0000-0000-0000-000000000003';
const _stranger = '00000000-0000-0000-0000-000000000004';
const _device = '10000000-0000-0000-0000-000000000001';
const _staleMemberDevice = '20000000-0000-0000-0000-000000000001';
const _freshMemberDevice = '20000000-0000-0000-0000-000000000002';

void main() {
  group('re-admission after eviction', () {
    test('an evicted member is added back with a fresh device set', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );

      final result = _applyReadmission(previous, localUserId: _owner);

      final next = (result as GroupControlAccepted).state;
      final readmitted = next.member(_member)!;
      expect(readmitted.membership, GroupMembershipState.active);
      expect(readmitted.deviceIds, [_freshMemberDevice]);
      expect(readmitted.role, GroupRole.member);
      // One row, not two: the stale entry is replaced rather than shadowed.
      expect(
        next.members.where((item) => item.userId == _member),
        hasLength(1),
      );
    });

    test('the re-admission is a membership change that advances the epoch', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );

      final next =
          (_applyReadmission(previous, localUserId: _owner)
                  as GroupControlAccepted)
              .state;

      expect(next.acceptedEpoch, previous.acceptedEpoch + 1);
      expect(next.controlRevision, previous.controlRevision + 1);
    });

    test('the re-admitted device reopens its own group', () {
      // The gapped device's own projection: it was evicted, so the group reads
      // `removed` until the Welcome that adds it back arrives.
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
        lifecycle: GroupLifecycle.removed,
      );
      expect(GroupAuthorization.permissionsFor(previous, _member), {
        GroupPermission.viewHistory,
      });

      final next =
          (_applyReadmission(previous, localUserId: _member)
                  as GroupControlAccepted)
              .state;

      expect(next.lifecycle, GroupLifecycle.active);
      expect(
        GroupAuthorization.allows(next, _member, GroupPermission.sendMessages),
        isTrue,
      );
    });

    test('an admin may re-admit under the default invitation policy', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );

      final result = _applyReadmission(
        previous,
        localUserId: _owner,
        actor: _admin,
      );

      expect(result, isA<GroupControlAccepted>());
    });

    test('a first-time invitation is unaffected', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );

      final next =
          (_applyReadmission(previous, localUserId: _owner, target: _stranger)
                  as GroupControlAccepted)
              .state;

      expect(next.member(_stranger)!.membership, GroupMembershipState.active);
      expect(next.member(_member)!.membership, GroupMembershipState.removed);
    });
  });

  group('states that are not re-admission targets', () {
    test('a live member cannot be invited again', () {
      final previous = _stateWith(_member);

      final result = _applyReadmission(previous, localUserId: _owner);

      expect(
        (result as GroupControlQuarantined).reason,
        GroupQuarantineReason.unauthorizedControl,
      );
    });

    test('a member whose eviction is still pending is refused', () {
      // ADR-039: `left` means the departure is announced but the leaf is still
      // in the ratchet tree holding the current epoch secret. Adding the same
      // client again before the owner commits the `Remove` would duplicate it.
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.left,
      );

      final result = _applyReadmission(previous, localUserId: _owner);

      expect(
        (result as GroupControlQuarantined).reason,
        GroupQuarantineReason.unauthorizedControl,
      );
    });

    test('the same member twice in one invite is refused', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );
      final invite = _signedInvite(
        previous,
        members: [_freshMember(_member), _freshMember(_member)],
      );

      final result = const GroupControlStateMachine().apply(
        previous: previous,
        signedControl: invite,
        localUserId: _owner,
      );

      expect(
        (result as GroupControlQuarantined).reason,
        GroupQuarantineReason.unauthorizedControl,
      );
    });

    test('a re-admission may not smuggle in a privileged role', () {
      final previous = _stateWith(
        _member,
        membership: GroupMembershipState.removed,
      );
      final invite = _signedInvite(
        previous,
        members: [
          GroupMember(
            userId: _member,
            displayName: 'Member',
            role: GroupRole.admin,
            deviceIds: const [_freshMemberDevice],
          ),
        ],
      );

      final result = const GroupControlStateMachine().apply(
        previous: previous,
        signedControl: invite,
        localUserId: _owner,
      );

      expect(
        (result as GroupControlQuarantined).reason,
        GroupQuarantineReason.unauthorizedControl,
      );
    });

    test('re-admission stays inside the member cap', () {
      final filler = [
        for (var index = 0; index < GroupState.maximumMembers - 2; index += 1)
          GroupMember(
            userId:
                '00000000-0000-0000-0000-0000000001${index.toString().padLeft(2, '0')}',
            displayName: 'Filler $index',
            role: GroupRole.member,
          ),
      ];
      final previous = GroupState(
        groupId: _groupId,
        metadata: const GroupMetadata(name: 'Team'),
        invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
        historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
        members: [
          GroupMember(
            userId: _owner,
            displayName: 'Owner',
            role: GroupRole.owner,
          ),
          GroupMember(
            userId: _member,
            displayName: 'Member',
            role: GroupRole.member,
            membership: GroupMembershipState.removed,
          ),
          ...filler,
        ],
        controlRevision: 2,
        controlStateHash: _repeat('10', 32),
        acceptedEpoch: 2,
      );
      expect(previous.activeMembers, hasLength(GroupState.maximumMembers - 1));

      expect(
        _applyReadmission(previous, localUserId: _owner),
        isA<GroupControlAccepted>(),
      );
      expect(
        _applyReadmission(
          previous,
          localUserId: _owner,
          extraTargets: [_stranger],
        ),
        isA<GroupControlQuarantined>(),
      );
    });
  });

  group('the removal that precedes a re-admission', () {
    test('an evicted member holds no permission but keeps its history', () {
      final live = _stateWith(_member);
      final removal = _signed(
        previous: live,
        actor: _owner,
        epoch: live.acceptedEpoch + 1,
        operation: const RemoveGroupMemberOperation(_member),
        controlHash: _repeat('31', 32),
      );

      final next =
          (const GroupControlStateMachine().apply(
                    previous: live,
                    signedControl: removal,
                    localUserId: _member,
                  )
                  as GroupControlAccepted)
              .state;

      expect(next.member(_member)!.membership, GroupMembershipState.removed);
      expect(next.lifecycle, GroupLifecycle.removed);
      expect(GroupAuthorization.permissionsFor(next, _member), {
        GroupPermission.viewHistory,
      });
      // And that evicted state is exactly what the re-admission consumes.
      expect(
        _applyReadmission(next, localUserId: _member),
        isA<GroupControlAccepted>(),
      );
    });
  });
}

GroupControlApplyResult _applyReadmission(
  GroupState previous, {
  required String localUserId,
  String actor = _owner,
  String target = _member,
  List<String> extraTargets = const [],
}) => const GroupControlStateMachine().apply(
  previous: previous,
  signedControl: _signedInvite(
    previous,
    actor: actor,
    members: [
      _freshMember(target),
      for (final extra in extraTargets) _freshMember(extra),
    ],
  ),
  localUserId: localUserId,
);

GroupMember _freshMember(String userId) => GroupMember(
  userId: userId,
  displayName: 'Member',
  role: GroupRole.member,
  verified: true,
  deviceIds: const [_freshMemberDevice],
);

GroupState _stateWith(
  String memberId, {
  GroupMembershipState membership = GroupMembershipState.active,
  GroupLifecycle lifecycle = GroupLifecycle.active,
}) => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Team'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: [
    GroupMember(userId: _owner, displayName: 'Owner', role: GroupRole.owner),
    GroupMember(userId: _admin, displayName: 'Admin', role: GroupRole.admin),
    GroupMember(
      userId: memberId,
      displayName: 'Member',
      role: GroupRole.member,
      membership: membership,
      deviceIds: const [_staleMemberDevice],
    ),
  ],
  controlRevision: 2,
  controlStateHash: _repeat('10', 32),
  acceptedEpoch: 2,
  lifecycle: lifecycle,
);

SignedGroupControlEvent _signedInvite(
  GroupState previous, {
  String actor = _owner,
  required List<GroupMember> members,
}) => _signed(
  previous: previous,
  actor: actor,
  epoch: previous.acceptedEpoch + 1,
  operation: InviteGroupMembersOperation(members),
  controlHash: _repeat('20', 32),
);

SignedGroupControlEvent _signed({
  required GroupState previous,
  required String actor,
  required int epoch,
  required GroupControlOperation operation,
  required String controlHash,
}) {
  final revision = previous.controlRevision + 1;
  final event = GroupControlEvent(
    eventId: revision.toRadixString(16).padLeft(32, '0'),
    groupId: _groupId,
    revision: revision,
    previousControlStateHash: previous.controlStateHash,
    mlsEpoch: epoch,
    mlsCommitHash: operation.changesMembership ? _repeat('77', 32) : null,
    signerUserId: actor,
    signerDeviceId: _device,
    createdMs: 200 + revision,
    operation: operation,
  );
  return SignedGroupControlEvent(
    event: event,
    controlStateHash: controlHash,
    canonicalBytes: Uint8List.fromList(
      utf8.encode(event.deterministicProjection),
    ),
    signature: Uint8List.fromList([1, 2, 3]),
  );
}

String _repeat(String pair, int count) => List.filled(count, pair).join();
