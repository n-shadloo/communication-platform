import 'dart:typed_data';

import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adversarial coverage for ADR-041.
///
/// The attacker is the member an owner or admin is evicting. It is given every
/// advantage the protocol allows:
///
/// * it sees the eviction branch before it authors its own, so it knows exactly
///   which hash it has to beat;
/// * it may grind its control state hash freely, because that hash is a SHA-256
///   over a signed descriptor whose 16-byte event id and `created_ms` are free
///   author-chosen fields — the Rust test
///   `an_author_grinds_the_control_state_hash_below_a_known_rival` measures the
///   real cost at about 24,500 candidate branches per second per core; and
/// * it is handed `00…0`, the smallest hash that can exist, so the assertions
///   below hold for every hash any amount of grinding could ever reach.
///
/// The eviction is handed `ff…f`, the largest. Under ADR-038's hash-only order
/// the attacker won every one of these cases; under ADR-041 it wins none.
const _owner = '10000000-0000-4000-8000-000000000001';
const _ownerDevice = '1a000000-0000-4000-8000-000000000001';
const _admin = '20000000-0000-4000-8000-000000000001';
const _adminDevice = '2a000000-0000-4000-8000-000000000001';
const _attacker = '30000000-0000-4000-8000-000000000001';
const _attackerDevice = '3a000000-0000-4000-8000-000000000001';
const _bystander = '40000000-0000-4000-8000-000000000001';
const _bystanderDevice = '4a000000-0000-4000-8000-000000000001';
const _newcomer = '50000000-0000-4000-8000-000000000001';
const _newcomerDevice = '5a000000-0000-4000-8000-000000000001';

final _groundHash = '00' * 32;
final _evictionHash = 'ff' * 32;
final _groupId = 'ab' * 32;

void main() {
  group('a ground branch never defeats its own eviction', () {
    for (final policy in GroupInvitationPolicy.values) {
      for (final attackerRole in [GroupRole.admin, GroupRole.member]) {
        for (final evictorRole in [GroupRole.owner, GroupRole.admin]) {
          final label =
              '${attackerRole.name} evicted by ${evictorRole.name} '
              'under ${policy.name}';
          test(label, () {
            final parent = _parent(attackerRole: attackerRole, policy: policy);
            final eviction = _evictionBranch(parent, evictorRole);
            if (eviction == null) {
              // An admin may only evict a plain member, so admin-evicts-admin
              // is not a reachable configuration; nothing to defend.
              expect(attackerRole, GroupRole.admin);
              expect(evictorRole, GroupRole.admin);
              return;
            }

            final authored = _authorableBranches(parent, hash: _groundHash);
            expect(
              authored,
              isNotEmpty,
              reason: 'the attacker must really have branches to grind',
            );
            for (final branch in authored.entries) {
              expect(
                GroupForkCanonicalOrder.outranks(eviction, [branch.value]),
                isTrue,
                reason:
                    'a ground ${branch.key} must not displace the eviction '
                    'in: $label',
              );
              expect(
                GroupForkCanonicalOrder.canonical([branch.value, eviction]),
                same(eviction),
              );
            }
          });
        }
      }
    }

    test('a plain member cannot reach the eviction class at all', () {
      final parent = _parent(
        attackerRole: GroupRole.member,
        policy: GroupInvitationPolicy.allMembers,
      );

      final classes = _authorableBranches(
        parent,
        hash: _groundHash,
      ).values.map((branch) => branch.precedence).toSet();

      expect(classes, isNot(contains(GroupControlPrecedence.eviction)));
      expect(classes, isNotEmpty);
    });

    test('an evicted admin cannot outrank the owner inside its own class', () {
      final parent = _parent(
        attackerRole: GroupRole.admin,
        policy: GroupInvitationPolicy.ownerAndAdmins,
      );
      final eviction = _evictionBranch(parent, GroupRole.owner)!;

      final counter = _authorableBranches(parent, hash: _groundHash).values
          .where(
            (branch) => branch.precedence == GroupControlPrecedence.eviction,
          )
          .toList(growable: false);

      // An admin under eviction can still author an eviction of its own, so the
      // class rank alone is not enough; the parent-roster authority rank is.
      expect(counter, isNotEmpty);
      for (final branch in counter) {
        expect(branch.signerRole, GroupRole.admin);
        expect(GroupForkCanonicalOrder.outranks(eviction, [branch]), isTrue);
      }
    });
  });

  group('grinding', () {
    test('reaches a hash below the eviction, which ADR-038 would have taken', () {
      final parent = _parent(
        attackerRole: GroupRole.admin,
        policy: GroupInvitationPolicy.ownerOnly,
      );
      final evictionHash = _digest('eviction branch');

      // 4,096 trials of the attacker's search: vary the free event id, keep the
      // smallest resulting hash. The digest here only stands in for SHA-256 —
      // the cost of the real loop is measured in the Rust core test.
      var best = 'ff' * 32;
      var beatsTheEviction = 0;
      for (var trial = 0; trial < 4096; trial += 1) {
        final candidate = _digest('attacker branch $trial');
        if (candidate.compareTo(evictionHash) < 0) beatsTheEviction += 1;
        if (candidate.compareTo(best) < 0) best = candidate;
      }

      expect(
        beatsTheEviction,
        greaterThan(0),
        reason: 'grinding must reach hashes below a known rival',
      );
      expect(best.compareTo(evictionHash), lessThan(0));

      // ADR-038 ordered on the hash alone and would have taken the ground
      // branch. ADR-041 reads the class and the roster first.
      final eviction = _branchFor(
        parent,
        signer: _owner,
        device: _ownerDevice,
        operation: const RemoveGroupMemberOperation(_attacker),
        hash: evictionHash,
      )!;
      final ground = _branchFor(
        parent,
        signer: _attacker,
        device: _attackerDevice,
        operation: const UpdateGroupMetadataOperation(
          GroupMetadata(name: 'Ground'),
        ),
        hash: best,
      )!;

      expect(
        ground.controlStateHash.compareTo(eviction.controlStateHash),
        lessThan(0),
      );
      expect(GroupForkCanonicalOrder.outranks(eviction, [ground]), isTrue);
    });

    test('stays useless when it is repeated at every revision', () {
      var parent = _parent(
        attackerRole: GroupRole.admin,
        policy: GroupInvitationPolicy.ownerAndAdmins,
      );
      const machine = GroupControlStateMachine();

      // Before the eviction lands the attacker always has something to grind,
      // which is exactly why the superseded rule could be replayed forever.
      for (var round = 0; round < 8; round += 1) {
        final authored = _authorableBranches(
          parent,
          hash: _digest('round $round'),
        );
        expect(authored, isNotEmpty);
        final eviction = _evictionBranch(parent, GroupRole.owner)!;
        for (final branch in authored.values) {
          expect(
            GroupForkCanonicalOrder.outranks(eviction, [branch]),
            isTrue,
            reason: 'round $round must not be winnable by regrinding',
          );
        }
        if (round < 7) continue;

        final applied = machine.apply(
          previous: parent,
          signedControl: _signed(
            parent: parent,
            signer: _owner,
            device: _ownerDevice,
            operation: const RemoveGroupMemberOperation(_attacker),
            hash: _evictionHash,
          ),
          localUserId: _owner,
        );
        expect(applied, isA<GroupControlAccepted>());
        parent = (applied as GroupControlAccepted).state;
      }

      expect(
        parent.member(_attacker)!.membership,
        GroupMembershipState.removed,
      );
      // And there is no next round: an evicted member authorizes nothing.
      expect(_authorableBranches(parent, hash: _groundHash), isEmpty);
    });
  });
}

/// Every branch the attacker can actually get past authentication, replay and
/// authorization at [parent], keyed by a readable operation label.
///
/// The filter is [GroupControlStateMachine], not a hand-written permission
/// table, so this enumerates the real attack surface rather than an assumed one.
Map<String, GroupForkBranch> _authorableBranches(
  GroupState parent, {
  required String hash,
}) {
  final branches = <String, GroupForkBranch>{};
  for (final (label, operation) in _candidateOperations(parent)) {
    final branch = _branchFor(
      parent,
      signer: _attacker,
      device: _attackerDevice,
      operation: operation,
      hash: hash,
    );
    if (branch != null) branches[label] = branch;
  }
  return branches;
}

/// Null when the state machine refuses the control, which is the honest answer
/// to "can this member author this branch at this revision".
GroupForkBranch? _branchFor(
  GroupState parent, {
  required String signer,
  required String device,
  required GroupControlOperation operation,
  required String hash,
}) {
  final signed = _signed(
    parent: parent,
    signer: signer,
    device: device,
    operation: operation,
    hash: hash,
  );
  final applied = const GroupControlStateMachine().apply(
    previous: parent,
    signedControl: signed,
    localUserId: _owner,
  );
  if (applied is! GroupControlAccepted) return null;
  return GroupForkCanonicalOrder.branchOf(
    parent: parent,
    signedControl: signed,
  );
}

GroupForkBranch? _evictionBranch(GroupState parent, GroupRole evictorRole) =>
    _branchFor(
      parent,
      signer: evictorRole == GroupRole.owner ? _owner : _admin,
      device: evictorRole == GroupRole.owner ? _ownerDevice : _adminDevice,
      operation: const RemoveGroupMemberOperation(_attacker),
      hash: _evictionHash,
    );

Iterable<(String, GroupControlOperation)> _candidateOperations(
  GroupState parent,
) sync* {
  yield (
    'metadata edit',
    const UpdateGroupMetadataOperation(GroupMetadata(name: 'Ground')),
  );
  for (final invitation in GroupInvitationPolicy.values) {
    for (final history in GroupHistorySharingPolicy.values) {
      yield (
        'policy change ${invitation.name}/${history.name}',
        UpdateGroupPoliciesOperation(
          invitationPolicy: invitation,
          historySharingPolicy: history,
        ),
      );
    }
  }
  yield (
    'invite',
    InviteGroupMembersOperation([
      GroupMember(
        userId: _newcomer,
        displayName: 'Newcomer',
        role: GroupRole.member,
        deviceIds: const [_newcomerDevice],
      ),
    ]),
  );
  yield ('leave', const LeaveGroupOperation());
  for (final member in parent.members) {
    if (member.userId == _attacker) continue;
    yield (
      'remove ${member.userId}',
      RemoveGroupMemberOperation(member.userId),
    );
    yield (
      'transfer ownership to ${member.userId}',
      TransferGroupOwnershipOperation(member.userId),
    );
    for (final role in GroupRole.values) {
      yield (
        'make ${member.userId} ${role.name}',
        ChangeGroupRoleOperation(targetUserId: member.userId, role: role),
      );
    }
  }
}

SignedGroupControlEvent _signed({
  required GroupState parent,
  required String signer,
  required String device,
  required GroupControlOperation operation,
  required String hash,
}) => SignedGroupControlEvent(
  event: GroupControlEvent(
    eventId: _digest('$signer|${operation.code}|$hash').substring(0, 32),
    groupId: parent.groupId,
    revision: parent.controlRevision + 1,
    previousControlStateHash: parent.controlStateHash,
    mlsEpoch: parent.acceptedEpoch + (operation.changesMembership ? 1 : 0),
    mlsCommitHash: operation.changesMembership ? 'c0' * 32 : null,
    signerUserId: signer,
    signerDeviceId: device,
    createdMs: 1,
    operation: operation,
  ),
  controlStateHash: hash,
  canonicalBytes: Uint8List.fromList(const [1]),
  signature: Uint8List.fromList(const [2]),
);

GroupState _parent({
  required GroupRole attackerRole,
  required GroupInvitationPolicy policy,
}) => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Forked'),
  invitationPolicy: policy,
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
    GroupMember(
      userId: _attacker,
      displayName: 'Attacker',
      role: attackerRole,
      deviceIds: const [_attackerDevice],
    ),
    GroupMember(
      userId: _bystander,
      displayName: 'Bystander',
      role: GroupRole.member,
      deviceIds: const [_bystanderDevice],
    ),
  ],
  controlRevision: 2,
  controlStateHash: '77' * 32,
  acceptedEpoch: 2,
);

/// A 32-byte hex digest standing in for the core's SHA-256 control state hash.
///
/// Only one property is needed here: changing the author-chosen input changes
/// the value, which is what makes the value grindable in the first place.
String _digest(String input) {
  var state = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    state = ((state ^ unit) * 0x01000193) & 0xffffffff;
  }
  final bytes = List<int>.generate(32, (index) {
    state = ((state ^ (index + 1)) * 0x01000193) & 0xffffffff;
    return (state >>> ((index % 4) * 8)) & 0xff;
  });
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
