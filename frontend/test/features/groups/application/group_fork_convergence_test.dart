import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/group_mls_inbound_coordinator.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = '10000000-0000-4000-8000-000000000001';
const _aliceDevice = '20000000-0000-4000-8000-000000000001';
const _bob = '30000000-0000-4000-8000-000000000001';
const _bobDevice = '40000000-0000-4000-8000-000000000001';
final _groupId = 'ab' * 32;
final _siblingEventId = 'cd' * 16;
final _canonicalEventId = 'ef' * 16;

void main() {
  // ADR-041 replaced ADR-038's hash-only order. These cases were rewritten for
  // the ordering key, because a rule that reads only the control state hash is
  // exactly the defect: the hash is author-chosen entropy, not evidence.
  group('canonical fork order', () {
    test('an eviction outranks a non-security sibling with a lower hash', () {
      final eviction = _branch(
        hash: 'ff' * 32,
        precedence: GroupControlPrecedence.eviction,
        role: GroupRole.owner,
      );
      final ground = _branch(
        hash: '00' * 32,
        precedence: GroupControlPrecedence.descriptive,
        role: GroupRole.admin,
      );

      expect(GroupForkCanonicalOrder.outranks(eviction, [ground]), isTrue);
      expect(GroupForkCanonicalOrder.outranks(ground, [eviction]), isFalse);
      expect(GroupForkCanonicalOrder.canonical([ground, eviction]), eviction);
    });

    test('within one class the parent roster authority decides', () {
      final owner = _branch(
        hash: 'ff' * 32,
        precedence: GroupControlPrecedence.eviction,
        role: GroupRole.owner,
        user: _bob,
      );
      final admin = _branch(
        hash: '00' * 32,
        precedence: GroupControlPrecedence.eviction,
        role: GroupRole.admin,
        user: _alice,
      );

      expect(GroupForkCanonicalOrder.outranks(owner, [admin]), isTrue);
      expect(GroupForkCanonicalOrder.outranks(admin, [owner]), isFalse);
    });

    test('is total and antisymmetric across two branches', () {
      final low = _branch(hash: 'aa' * 32, user: _alice);
      final high = _branch(hash: 'bb' * 32, user: _bob);

      expect(GroupForkCanonicalOrder.outranks(low, [high]), isTrue);
      expect(GroupForkCanonicalOrder.outranks(high, [low]), isFalse);
      expect(GroupForkCanonicalOrder.canonical([high, low]), low);
      expect(GroupForkCanonicalOrder.canonical([low, high]), low);
    });

    test('is case insensitive so hex casing cannot flip the winner', () {
      final upper = _branch(hash: 'AA' * 32, user: _alice.toUpperCase());
      final lower = _branch(hash: 'bb' * 32, user: _bob);

      expect(GroupForkCanonicalOrder.outranks(upper, [lower]), isTrue);
      expect(GroupForkCanonicalOrder.outranks(lower, [upper]), isFalse);
      expect(GroupForkCanonicalOrder.canonical([lower, upper]), upper);
    });

    test('an identical branch never outranks itself', () {
      final branch = _branch(hash: 'aa' * 32);
      expect(GroupForkCanonicalOrder.outranks(branch, [branch]), isFalse);
    });

    test('the hash decides only when one device signed both branches', () {
      final low = _branch(hash: '02' * 32, eventId: '01' * 16);
      final high = _branch(hash: 'c3' * 32, eventId: '02' * 16);

      expect(GroupForkCanonicalOrder.outranks(low, [high]), isTrue);
      expect(GroupForkCanonicalOrder.canonical([high, low]), low);
      // Same class, role, user and device: both branches are the equivocating
      // device's own, so ordering them decides nothing an author could not
      // already decide by choosing which one to send.
      expect(low.signerUserId, high.signerUserId);
      expect(low.signerDeviceId, high.signerDeviceId);
    });

    test('every device picks the same winner regardless of arrival order', () {
      final branches = [
        _branch(hash: 'ff' * 32, user: _alice),
        _branch(
          hash: '10' * 32,
          precedence: GroupControlPrecedence.eviction,
          role: GroupRole.admin,
          user: _bob,
        ),
        _branch(hash: '02' * 32, user: _bob),
        _branch(
          hash: 'c3' * 32,
          precedence: GroupControlPrecedence.membership,
          user: _alice,
        ),
      ];
      final winners = [
        GroupForkCanonicalOrder.canonical(branches),
        GroupForkCanonicalOrder.canonical(branches.reversed),
        GroupForkCanonicalOrder.canonical(
          branches.toList()..sort(GroupForkCanonicalOrder.compare),
        ),
      ];
      expect(winners.map((branch) => branch.eventId).toSet(), hasLength(1));
      expect(winners.first.precedence, GroupControlPrecedence.eviction);
    });

    test('rejects an empty branch set instead of inventing a winner', () {
      expect(
        () => GroupForkCanonicalOrder.canonical(const []),
        throwsFormatException,
      );
    });
  });

  group('fork branch keys', () {
    test('read authority from the parent, never from the branch', () {
      final parent = _state();
      final signed = _signedControl(
        parent: parent,
        signerUserId: _alice,
        signerDeviceId: _aliceDevice,
        operation: const TransferGroupOwnershipOperation(_bob),
        controlStateHash: '11' * 32,
      );

      final branch = GroupForkCanonicalOrder.branchOf(
        parent: parent,
        signedControl: signed,
      );

      // The operation demotes its own signer, but ordering uses the role the
      // signer held in the shared parent.
      expect(branch, isNotNull);
      expect(branch!.signerRole, GroupRole.owner);
      expect(branch.precedence, GroupControlPrecedence.authority);
    });

    test('refuse a signer that is not an active member of the parent', () {
      final parent = _state();
      final stranger = _signedControl(
        parent: parent,
        signerUserId: '90000000-0000-4000-8000-000000000001',
        signerDeviceId: '91000000-0000-4000-8000-000000000001',
        operation: const UpdateGroupMetadataOperation(
          GroupMetadata(name: 'Renamed'),
        ),
        controlStateHash: '00' * 32,
      );

      expect(
        GroupForkCanonicalOrder.branchOf(
          parent: parent,
          signedControl: stranger,
        ),
        isNull,
      );
    });
  });

  group('inbound fork resolution', () {
    test(
      'a canonical local branch records the sibling and keeps running',
      () async {
        final crypto = _ForkCrypto(
          GroupForkLocalBranchCanonical(supersededEventIds: [_siblingEventId]),
        );
        final result = await _coordinator(crypto).inspect(_sibling());

        final commit = (result as Success<PreparedGroupInboxCommit>).value;
        expect(commit, isA<PreparedGroupInboxForkResolution>());
        final fork = commit as PreparedGroupInboxForkResolution;
        expect(fork.localBranchRetained, isTrue);
        expect(fork.record.reason, GroupQuarantineReason.siblingCommit);
        expect(fork.record.groupId, _groupId);
        expect(fork.opaqueEventId, 'group-fork:$_siblingEventId');
        // The audit digest is the verified event id, not a Dart-computed hash.
        expect(fork.record.opaqueDigest, List<int>.filled(16, 0xcd));
      },
    );

    test('a superseded local branch quarantines for remove/re-add', () async {
      final crypto = _ForkCrypto(
        GroupForkLocalBranchSuperseded(
          canonicalEventId: _canonicalEventId,
          canonicalControlStateHash: '01' * 32,
          canonicalSignerUserId: _bob,
        ),
      );
      final result = await _coordinator(crypto).inspect(_sibling());

      final fork =
          (result as Success<PreparedGroupInboxCommit>).value
              as PreparedGroupInboxForkResolution;
      expect(fork.localBranchRetained, isFalse);
      expect(fork.record.reason, GroupQuarantineReason.siblingCommit);
      expect(fork.siblingSignerUserId, _bob);
      expect(fork.opaqueEventId, 'group-fork:$_canonicalEventId');
    });

    test('a non-orderable control keeps its original failure', () async {
      final crypto = _ForkCrypto(null);
      final result = await _coordinator(crypto).inspect(_sibling());

      expect(
        result,
        isA<FailureResult<PreparedGroupInboxCommit>>().having(
          (value) => value.failure,
          'failure',
          const SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        ),
      );
    });

    test('a sibling for a different group is never ordered', () async {
      final crypto = _ForkCrypto(
        GroupForkLocalBranchCanonical(supersededEventIds: [_siblingEventId]),
        probeGroupId: 'cc' * 32,
      );
      final result = await _coordinator(crypto).inspect(_sibling());

      expect(result, isA<FailureResult<PreparedGroupInboxCommit>>());
      expect(crypto.reconcileCalls, 0);
    });
  });
}

GroupForkBranch _branch({
  required String hash,
  String? eventId,
  GroupControlPrecedence precedence = GroupControlPrecedence.descriptive,
  GroupRole role = GroupRole.member,
  String user = _alice,
  String device = _aliceDevice,
}) => GroupForkBranch(
  eventId: eventId ?? _canonicalEventId,
  controlStateHash: hash,
  precedence: precedence,
  signerRole: role,
  signerUserId: user,
  signerDeviceId: device,
);

SignedGroupControlEvent _signedControl({
  required GroupState parent,
  required String signerUserId,
  required String signerDeviceId,
  required GroupControlOperation operation,
  required String controlStateHash,
}) => SignedGroupControlEvent(
  event: GroupControlEvent(
    eventId: _canonicalEventId,
    groupId: parent.groupId,
    revision: parent.controlRevision + 1,
    previousControlStateHash: parent.controlStateHash,
    mlsEpoch: parent.acceptedEpoch + (operation.changesMembership ? 1 : 0),
    mlsCommitHash: operation.changesMembership ? 'c0' * 32 : null,
    signerUserId: signerUserId,
    signerDeviceId: signerDeviceId,
    createdMs: 1,
    operation: operation,
  ),
  controlStateHash: controlStateHash,
  canonicalBytes: Uint8List.fromList(const [1]),
  signature: Uint8List.fromList(const [2]),
);

GroupMlsInboundCoordinator _coordinator(_ForkCrypto crypto) =>
    GroupMlsInboundCoordinator(
      repository: _Repository(),
      crypto: crypto,
      localUserId: _alice,
      localDeviceId: _aliceDevice,
      clock: () => DateTime.utc(2026, 8, 16),
    );

Uint8List _sibling() => Uint8List.fromList(List<int>.filled(32, 0x5a));

GroupState _state() => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Forked'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: [
    GroupMember(
      userId: _alice,
      displayName: 'Alice',
      role: GroupRole.owner,
      deviceIds: const [_aliceDevice],
    ),
    GroupMember(
      userId: _bob,
      displayName: 'Bob',
      role: GroupRole.admin,
      deviceIds: const [_bobDevice],
    ),
  ],
  controlRevision: 2,
  controlStateHash: '77' * 32,
  acceptedEpoch: 2,
);

final class _Repository implements GroupRepositoryPort {
  @override
  Future<Result<GroupState?>> readGroup(String groupId) async =>
      Result.success(groupId == _groupId ? _state() : null);

  @override
  Future<Result<Uint8List?>> readOpaqueMlsState(String groupId) async =>
      Result.success(Uint8List.fromList([9]));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Fails every ordinary control so the fork path is the only one under test.
final class _ForkCrypto implements GroupMlsCryptoPort {
  _ForkCrypto(this.resolution, {String? probeGroupId})
    : probeGroupId = probeGroupId ?? _groupId;

  final GroupForkResolution? resolution;
  final String probeGroupId;
  var reconcileCalls = 0;

  @override
  Future<Result<GroupMlsTransportProbe>> probeIncomingTransport(
    Uint8List mlsObject,
  ) async => Result.success(
    GroupMlsTransportProbe(
      kind: GroupMlsTransportKind.control,
      groupId: probeGroupId,
    ),
  );

  @override
  Future<Result<PreparedGroupTransition>> inspectIncomingControl({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required Uint8List mlsObject,
    required String localUserId,
    required String localDeviceId,
  }) async => const Result.failure(
    SecurityFailure(SecurityFailureKind.unauthenticatedInput),
  );

  @override
  Future<Result<GroupForkResolution>> reconcileFork({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required List<Uint8List> siblingCommits,
    required String localUserId,
    required String localDeviceId,
  }) async {
    reconcileCalls += 1;
    expect(siblingCommits, hasLength(1));
    expect(localUserId, _alice);
    expect(localDeviceId, _aliceDevice);
    final value = resolution;
    return value == null
        ? const Result.failure(
            SecurityFailure(SecurityFailureKind.unauthenticatedInput),
          )
        : Result.success(value);
  }

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
