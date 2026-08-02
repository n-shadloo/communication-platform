import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _owner = '00000000-0000-0000-0000-000000000001';
const _admin = '00000000-0000-0000-0000-000000000002';
const _member = '00000000-0000-0000-0000-000000000003';
const _newMember = '00000000-0000-0000-0000-000000000004';
const _device = '10000000-0000-0000-0000-000000000001';

void main() {
  group('group authorization', () {
    test('owner, admin, and member permissions obey policy and hierarchy', () {
      for (final policy in GroupInvitationPolicy.values) {
        final state = _state(invitationPolicy: policy);
        expect(
          GroupAuthorization.allows(
            state,
            _owner,
            GroupPermission.transferOwnership,
          ),
          isTrue,
        );
        expect(
          GroupAuthorization.allows(
            state,
            _admin,
            GroupPermission.editMetadata,
          ),
          isTrue,
        );
        expect(
          GroupAuthorization.allows(
            state,
            _admin,
            GroupPermission.editHistorySharingPolicy,
          ),
          isFalse,
        );
        expect(
          GroupAuthorization.canRemove(
            state,
            actorUserId: _admin,
            targetUserId: _member,
          ),
          isTrue,
        );
        expect(
          GroupAuthorization.canRemove(
            state,
            actorUserId: _admin,
            targetUserId: _owner,
          ),
          isFalse,
        );
        expect(
          GroupAuthorization.allows(
            state,
            _member,
            GroupPermission.inviteMembers,
          ),
          policy == GroupInvitationPolicy.allMembers,
        );
      }
    });

    test('removed and queue-gap states expose history but no mutations', () {
      final removedMembers = [
        for (final item in _members())
          item.userId == _member
              ? item.copyWith(membership: GroupMembershipState.removed)
              : item,
      ];
      final removed = _state(members: removedMembers);
      expect(GroupAuthorization.permissionsFor(removed, _member), {
        GroupPermission.viewHistory,
      });

      final gap = _state(lifecycle: GroupLifecycle.queueGapRejoinRequired);
      for (final actor in [_owner, _admin, _member]) {
        expect(GroupAuthorization.permissionsFor(gap, actor), {
          GroupPermission.viewHistory,
        });
      }
      expect(
        GroupAuthorization.permissionsFor(
          _state(),
          '00000000-0000-0000-0000-000000000099',
        ),
        isEmpty,
      );
    });

    test('owner must transfer ownership before leaving a non-empty group', () {
      final state = _state();
      expect(GroupAuthorization.canLeave(state, _owner), isFalse);
      expect(GroupAuthorization.canLeave(state, _member), isTrue);
    });
  });

  group('deterministic controls and state machine', () {
    test(
      'member input order cannot change the canonical control projection',
      () {
        final left = GroupControlEvent(
          eventId: _repeat('11', 16),
          groupId: _groupId,
          revision: 1,
          previousControlStateHash: null,
          mlsEpoch: 0,
          mlsCommitHash: _repeat('22', 32),
          signerUserId: _owner,
          signerDeviceId: _device,
          createdMs: 100,
          operation: CreateGroupOperation(
            metadata: const GroupMetadata(name: 'Team'),
            invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
            historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
            initialMembers: _members().reversed,
          ),
        );
        final right = GroupControlEvent(
          eventId: _repeat('11', 16),
          groupId: _groupId,
          revision: 1,
          previousControlStateHash: null,
          mlsEpoch: 0,
          mlsCommitHash: _repeat('22', 32),
          signerUserId: _owner,
          signerDeviceId: _device,
          createdMs: 100,
          operation: CreateGroupOperation(
            metadata: const GroupMetadata(name: 'Team'),
            invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
            historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
            initialMembers: _members(),
          ),
        );
        expect(left.deterministicProjection, right.deterministicProjection);
      },
    );

    test(
      'unauthorized and malformed-chain controls quarantine without mutation',
      () {
        const machine = GroupControlStateMachine();
        final state = _state();
        final unauthorized = _signed(
          revision: 2,
          previousHash: state.controlStateHash,
          actor: _member,
          operation: const UpdateGroupMetadataOperation(
            GroupMetadata(name: 'Forged'),
          ),
          controlHash: _repeat('31', 32),
        );
        final result = machine.apply(
          previous: state,
          signedControl: unauthorized,
          localUserId: _member,
        );
        expect(result, isA<GroupControlQuarantined>());
        expect(
          (result as GroupControlQuarantined).reason,
          GroupQuarantineReason.unauthorizedControl,
        );
        expect(result.state, same(state));

        final broken = _signed(
          revision: 3,
          previousHash: _repeat('ff', 32),
          actor: _owner,
          operation: const UpdateGroupMetadataOperation(
            GroupMetadata(name: 'Broken'),
          ),
          controlHash: _repeat('32', 32),
        );
        final brokenResult = machine.apply(
          previous: state,
          signedControl: broken,
          localUserId: _owner,
        );
        expect(
          (brokenResult as GroupControlQuarantined).reason,
          GroupQuarantineReason.brokenControlChain,
        );
      },
    );

    test('concurrent admin/member changes quarantine the sibling revision', () {
      const machine = GroupControlStateMachine();
      final state = _state(invitationPolicy: GroupInvitationPolicy.allMembers);
      final adminChange = _signed(
        revision: 2,
        previousHash: state.controlStateHash,
        actor: _admin,
        operation: const UpdateGroupMetadataOperation(
          GroupMetadata(name: 'Admin update'),
        ),
        controlHash: _repeat('41', 32),
      );
      final memberInvite = _signed(
        revision: 2,
        previousHash: state.controlStateHash,
        actor: _member,
        epoch: 2,
        operation: InviteGroupMembersOperation([
          GroupMember(
            userId: _newMember,
            displayName: 'New',
            role: GroupRole.member,
          ),
        ]),
        controlHash: _repeat('42', 32),
      );
      final accepted = machine.apply(
        previous: state,
        signedControl: adminChange,
        localUserId: _owner,
      );
      expect(accepted, isA<GroupControlAccepted>());
      final sibling = machine.apply(
        previous: (accepted as GroupControlAccepted).state,
        signedControl: memberInvite,
        localUserId: _owner,
      );
      expect(
        (sibling as GroupControlQuarantined).reason,
        GroupQuarantineReason.siblingCommit,
      );
    });

    test('all valid owner role transitions preserve exactly one owner', () {
      const machine = GroupControlStateMachine();
      for (final target in [_admin, _member]) {
        final state = _state();
        final transfer = _signed(
          revision: 2,
          previousHash: state.controlStateHash,
          actor: _owner,
          operation: TransferGroupOwnershipOperation(target),
          controlHash: target == _admin ? _repeat('51', 32) : _repeat('52', 32),
        );
        final result = machine.apply(
          previous: state,
          signedControl: transfer,
          localUserId: _owner,
        );
        final next = (result as GroupControlAccepted).state;
        expect(
          next.activeMembers
              .where((item) => item.role == GroupRole.owner)
              .length,
          1,
        );
        expect(next.member(target)!.role, GroupRole.owner);
        expect(next.member(_owner)!.role, GroupRole.admin);
      }
    });
  });
}

GroupState _state({
  GroupInvitationPolicy invitationPolicy = GroupInvitationPolicy.ownerAndAdmins,
  GroupLifecycle lifecycle = GroupLifecycle.active,
  List<GroupMember>? members,
}) => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Team'),
  invitationPolicy: invitationPolicy,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: members ?? _members(),
  controlRevision: 1,
  controlStateHash: _repeat('10', 32),
  acceptedEpoch: 1,
  lifecycle: lifecycle,
);

List<GroupMember> _members() => [
  GroupMember(userId: _owner, displayName: 'Owner', role: GroupRole.owner),
  GroupMember(userId: _admin, displayName: 'Admin', role: GroupRole.admin),
  GroupMember(userId: _member, displayName: 'Member', role: GroupRole.member),
];

SignedGroupControlEvent _signed({
  required int revision,
  required String previousHash,
  required String actor,
  required GroupControlOperation operation,
  required String controlHash,
  int epoch = 1,
}) {
  final event = GroupControlEvent(
    eventId: revision.toRadixString(16).padLeft(32, '0'),
    groupId: _groupId,
    revision: revision,
    previousControlStateHash: previousHash,
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
