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
  group('canonical fork order', () {
    test('is total and antisymmetric across two branches', () {
      const low = 'aa11';
      const high = 'bb22';

      expect(GroupForkCanonicalOrder.outranks(low, const [high]), isTrue);
      expect(GroupForkCanonicalOrder.outranks(high, const [low]), isFalse);
      expect(GroupForkCanonicalOrder.canonical(const [high, low]), low);
      expect(GroupForkCanonicalOrder.canonical(const [low, high]), low);
    });

    test('is case insensitive so hex casing cannot flip the winner', () {
      expect(GroupForkCanonicalOrder.outranks('AA11', const ['bb22']), isTrue);
      expect(GroupForkCanonicalOrder.outranks('BB22', const ['aa11']), isFalse);
      expect(GroupForkCanonicalOrder.canonical(const ['BB22', 'Aa11']), 'aa11');
    });

    test('an identical hash never outranks itself', () {
      expect(GroupForkCanonicalOrder.outranks('aa11', const ['aa11']), isFalse);
    });

    test('every device picks the same winner regardless of arrival order', () {
      const branches = ['ff', '10', '7a', '02', 'c3'];
      final orders = [
        GroupForkCanonicalOrder.canonical(branches),
        GroupForkCanonicalOrder.canonical(branches.reversed),
        GroupForkCanonicalOrder.canonical(branches.toList()..sort()),
      ];
      expect(orders.toSet(), {'02'});
    });

    test('rejects an empty branch set instead of inventing a winner', () {
      expect(
        () => GroupForkCanonicalOrder.canonical(const []),
        throwsFormatException,
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
