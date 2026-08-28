import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _owner = '00000000-0000-0000-0000-000000000001';
const _admin = '00000000-0000-0000-0000-000000000002';
const _member = '00000000-0000-0000-0000-000000000003';
const _ownerDevice = '10000000-0000-0000-0000-000000000001';
const _memberDevice = '10000000-0000-0000-0000-000000000003';

void main() {
  group('leave carries no Commit', () {
    test('a leave is not a membership-changing control', () {
      // RFC 9420 12.4 forbids a Commit that removes its own committer, so the
      // departing member has no Commit to bind and must not claim one.
      expect(const LeaveGroupOperation().changesMembership, isFalse);
      expect(
        const RemoveGroupMemberOperation(_member).changesMembership,
        isTrue,
      );
    });

    test('a leave keeps the epoch and the remove advances it', () {
      final state = _state();
      final left = _apply(state, _leave(state, _member));
      expect(left.acceptedEpoch, state.acceptedEpoch);
      expect(left.member(_member)!.membership, GroupMembershipState.left);

      final evicted = _apply(left, _remove(left, _member));
      expect(evicted.member(_member)!.membership, GroupMembershipState.removed);
    });
  });

  group('departed members stay evictable', () {
    test('the owner may still remove a member that announced a leave', () {
      final left = _apply(_state(), _leave(_state(), _member));
      expect(
        GroupAuthorization.canRemove(
          left,
          actorUserId: _owner,
          targetUserId: _member,
        ),
        isTrue,
        reason: 'a departed leaf still holds the epoch secret until evicted',
      );
    });

    test('an already evicted member is not a target again', () {
      final left = _apply(_state(), _leave(_state(), _member));
      final evicted = _apply(left, _remove(left, _member));
      expect(
        GroupAuthorization.canRemove(
          evicted,
          actorUserId: _owner,
          targetUserId: _member,
        ),
        isFalse,
      );
      expect(GroupAuthorization.isEvictable(evicted.member(_member)!), isFalse);
    });

    test('the owner is never an eviction target', () {
      final state = _state();
      expect(
        GroupAuthorization.canRemove(
          state,
          actorUserId: _admin,
          targetUserId: _owner,
        ),
        isFalse,
      );
    });
  });

  group('leave authorization', () {
    test('an owner cannot abandon a group that still has members', () {
      expect(GroupAuthorization.canLeave(_state(), _owner), isFalse);
      expect(GroupAuthorization.canLeave(_state(), _member), isTrue);
    });

    test('a sole owner may leave and needs no committer', () {
      final solo = GroupState(
        groupId: _groupId,
        metadata: const GroupMetadata(name: 'Solo'),
        invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
        historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
        members: [
          GroupMember(
            userId: _owner,
            displayName: 'Owner',
            role: GroupRole.owner,
            deviceIds: const [_ownerDevice],
          ),
        ],
        controlRevision: 1,
        controlStateHash: _repeat('01', 32),
        acceptedEpoch: 1,
      );
      expect(GroupAuthorization.canLeave(solo, _owner), isTrue);

      final left = _apply(solo, _leave(solo, _owner), localUserId: _owner);
      expect(left.lifecycle, GroupLifecycle.left);
      expect(
        left.members.any(
          (member) => member.membership == GroupMembershipState.left,
        ),
        isTrue,
      );
    });

    test('a non-member cannot leave', () {
      expect(
        GroupAuthorization.canLeave(
          _state(),
          '00000000-0000-0000-0000-0000000000ff',
        ),
        isFalse,
      );
    });

    test('a departed member cannot leave twice', () {
      final left = _apply(_state(), _leave(_state(), _member));
      expect(GroupAuthorization.canLeave(left, _member), isFalse);
      expect(
        const GroupControlStateMachine().apply(
          previous: left,
          signedControl: _signed(
            revision: left.controlRevision + 1,
            previousHash: left.controlStateHash,
            actor: _member,
            operation: const LeaveGroupOperation(),
            controlHash: _repeat('cc', 32),
            epoch: left.acceptedEpoch,
          ),
          localUserId: _owner,
        ),
        isNot(isA<GroupControlAccepted>()),
      );
    });
  });
}

/// [localUserId] selects whose projection is produced. The leaver's own view
/// moves to [GroupLifecycle.left]; every remaining member keeps a live group.
GroupState _apply(
  GroupState previous,
  SignedGroupControlEvent control, {
  String localUserId = _owner,
}) {
  final applied = const GroupControlStateMachine().apply(
    previous: previous,
    signedControl: control,
    localUserId: localUserId,
  );
  expect(applied, isA<GroupControlAccepted>());
  return (applied as GroupControlAccepted).state;
}

SignedGroupControlEvent _leave(GroupState state, String actor) => _signed(
  revision: state.controlRevision + 1,
  previousHash: state.controlStateHash,
  actor: actor,
  operation: const LeaveGroupOperation(),
  controlHash: _repeat('aa', 32),
  epoch: state.acceptedEpoch,
);

SignedGroupControlEvent _remove(GroupState state, String target) => _signed(
  revision: state.controlRevision + 1,
  previousHash: state.controlStateHash,
  actor: _owner,
  operation: RemoveGroupMemberOperation(target),
  controlHash: _repeat('bb', 32),
  epoch: state.acceptedEpoch + 1,
);

GroupState _state() => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Leave'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: [
    GroupMember(
      userId: _owner,
      displayName: 'Owner',
      role: GroupRole.owner,
      deviceIds: const [_ownerDevice],
    ),
    GroupMember(userId: _admin, displayName: 'Admin', role: GroupRole.admin),
    GroupMember(
      userId: _member,
      displayName: 'Member',
      role: GroupRole.member,
      deviceIds: const [_memberDevice],
    ),
  ],
  controlRevision: 1,
  controlStateHash: _repeat('01', 32),
  acceptedEpoch: 1,
);

SignedGroupControlEvent _signed({
  required int revision,
  required String previousHash,
  required String actor,
  required GroupControlOperation operation,
  required String controlHash,
  required int epoch,
}) {
  final event = GroupControlEvent(
    eventId: revision.toRadixString(16).padLeft(32, '0'),
    groupId: _groupId,
    revision: revision,
    previousControlStateHash: previousHash,
    mlsEpoch: epoch,
    mlsCommitHash: operation.changesMembership ? _repeat('77', 32) : null,
    signerUserId: actor,
    signerDeviceId: actor == _owner ? _ownerDevice : _memberDevice,
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
