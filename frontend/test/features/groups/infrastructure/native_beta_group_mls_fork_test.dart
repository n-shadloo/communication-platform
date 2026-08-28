import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/application/ports/beta_mls_crypto_port.dart';
import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/native_beta_group_mls.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end cover for ADR-041 at the adapter boundary.
///
/// Both devices see the same two branches at revision 2 and must converge on
/// the owner's eviction, even though the competing branch carries `00…0` — the
/// smallest control state hash that can exist, and therefore the best outcome
/// any amount of grinding could reach — while the eviction carries `ff…f`, the
/// worst. Under ADR-038's hash-only order both assertions below were inverted.
const _alice = '10000000-0000-4000-8000-000000000001';
const _aliceDevice = '20000000-0000-4000-8000-000000000001';
const _bob = '30000000-0000-4000-8000-000000000001';
const _bobDevice = '40000000-0000-4000-8000-000000000001';

final _groupId = '06' * 32;
final _createHash = '09' * 32;
final _evictionHash = 'ff' * 32;
final _groundHash = '00' * 32;
final _createEventId = '31' * 16;
final _evictionEventId = '32' * 16;

void main() {
  test(
    'the evicting owner keeps its branch against a ground sibling',
    () async {
      final crypto = _Crypto();
      final sibling = await _groundSibling(crypto);
      final adapter = NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: _Ids(),
        transcript: _Transcript(evictionBranch: true),
      );

      final resolved = await adapter.reconcileFork(
        current: _postEviction(),
        currentOpaqueMlsState: Uint8List.fromList([1]),
        siblingCommits: [sibling],
        localUserId: _alice,
        localDeviceId: _aliceDevice,
      );

      final resolution =
          (resolved as Success<GroupForkResolution>).value
              as GroupForkLocalBranchCanonical;
      expect(resolution.supersededEventIds, hasLength(1));
      // The sibling's hash is below the eviction's, so a hash-only order would
      // have quarantined the owner and defeated the eviction.
      expect(_groundHash.compareTo(_evictionHash), lessThan(0));
    },
  );

  test(
    'a device that took the ground branch converges on the eviction',
    () async {
      final crypto = _Crypto();
      final eviction = await _evictionSibling(crypto);
      final adapter = NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: _Ids(),
        transcript: _Transcript(evictionBranch: false),
      );

      final resolved = await adapter.reconcileFork(
        current: _postGroundEdit(),
        currentOpaqueMlsState: Uint8List.fromList([1]),
        siblingCommits: [eviction],
        localUserId: _bob,
        localDeviceId: _bobDevice,
      );

      final resolution =
          (resolved as Success<GroupForkResolution>).value
              as GroupForkLocalBranchSuperseded;
      expect(resolution.canonicalControlStateHash, _evictionHash);
      expect(resolution.canonicalSignerUserId, _alice);
    },
  );
}

/// The branch the member under eviction grinds: a metadata edit, which an admin
/// may author at every revision, signed with the smallest hash that can exist.
Future<Uint8List> _groundSibling(_Crypto crypto) async {
  crypto
    ..signerUserId = _bob
    ..signerDeviceId = _bobDevice
    ..signedHash = _groundHash;
  final prepared =
      await NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: _Ids(),
      ).prepareControl(
        current: _parent(),
        currentOpaqueMlsState: Uint8List.fromList([1]),
        operation: _groundEdit,
        actorUserId: _bob,
        actorDeviceId: _bobDevice,
        createdMs: 1_700_000_000_002,
      );
  return (prepared as Success<PreparedGroupTransition>).value.mlsObject;
}

const _groundEdit = UpdateGroupMetadataOperation(GroupMetadata(name: 'Ground'));

/// Alice's removal of Bob at revision 2, signed with the largest hash.
Future<Uint8List> _evictionSibling(_Crypto crypto) async {
  crypto
    ..signerUserId = _alice
    ..signerDeviceId = _aliceDevice
    ..signedHash = _evictionHash;
  final prepared =
      await NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: _Ids(),
      ).prepareControl(
        current: _parent(),
        currentOpaqueMlsState: Uint8List.fromList([1]),
        operation: const RemoveGroupMemberOperation(_bob),
        actorUserId: _alice,
        actorDeviceId: _aliceDevice,
        createdMs: 1_700_000_000_003,
      );
  return (prepared as Success<PreparedGroupTransition>).value.mlsObject;
}

GroupState _parent() => GroupState(
  groupId: _groupId,
  metadata: const GroupMetadata(name: 'Before'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: _roster(),
  controlRevision: 1,
  controlStateHash: _createHash,
  acceptedEpoch: 1,
);

GroupState _postEviction() => _parent().copyWith(
  members: [
    _roster().first,
    _roster().last.copyWith(membership: GroupMembershipState.removed),
  ],
  controlRevision: 2,
  controlStateHash: _evictionHash,
  acceptedEpoch: 2,
);

GroupState _postGroundEdit() => _parent().copyWith(
  metadata: const GroupMetadata(name: 'Ground'),
  controlRevision: 2,
  controlStateHash: _groundHash,
);

List<GroupMember> _roster() => [
  GroupMember(
    userId: _alice,
    displayName: 'Alice',
    role: GroupRole.owner,
    verified: true,
    deviceIds: const [_aliceDevice],
  ),
  GroupMember(
    userId: _bob,
    displayName: 'Bob',
    role: GroupRole.admin,
    verified: true,
    deviceIds: const [_bobDevice],
  ),
];

GroupControlTranscriptEntry _entry(
  GroupControlEvent event,
  String controlStateHash,
) => GroupControlTranscriptEntry(
  signedControl: SignedGroupControlEvent(
    event: event,
    controlStateHash: controlStateHash,
    canonicalBytes: Uint8List.fromList([7]),
    signature: Uint8List.fromList(List<int>.filled(64, 8)),
  ),
  signedPayload: Uint8List.fromList('CPGCV001'.codeUnits),
  signerAuthenticationProof: Uint8List.fromList('CPBRV001'.codeUnits),
);

final class _Transcript implements GroupControlTranscriptPort {
  const _Transcript({required this.evictionBranch});

  /// Whether the locally accepted revision-2 branch is the owner's eviction or
  /// the ground metadata edit the member under eviction authored.
  final bool evictionBranch;

  @override
  Future<Result<List<GroupControlTranscriptEntry>>> readVerifiedTranscript(
    String groupId,
  ) async => Result.success([
    _entry(
      GroupControlEvent(
        eventId: _createEventId,
        groupId: groupId,
        revision: 1,
        previousControlStateHash: null,
        mlsEpoch: 1,
        mlsCommitHash: '03' * 32,
        signerUserId: _alice,
        signerDeviceId: _aliceDevice,
        createdMs: 1_700_000_000_000,
        operation: CreateGroupOperation(
          metadata: const GroupMetadata(name: 'Before'),
          invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
          historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
          initialMembers: _roster(),
        ),
      ),
      _createHash,
    ),
    if (evictionBranch)
      _entry(
        GroupControlEvent(
          eventId: _evictionEventId,
          groupId: groupId,
          revision: 2,
          previousControlStateHash: _createHash,
          mlsEpoch: 2,
          mlsCommitHash: '15' * 32,
          signerUserId: _alice,
          signerDeviceId: _aliceDevice,
          createdMs: 1_700_000_000_003,
          operation: const RemoveGroupMemberOperation(_bob),
        ),
        _evictionHash,
      )
    else
      _entry(
        GroupControlEvent(
          eventId: '33' * 16,
          groupId: groupId,
          revision: 2,
          previousControlStateHash: _createHash,
          mlsEpoch: 1,
          mlsCommitHash: null,
          signerUserId: _bob,
          signerDeviceId: _bobDevice,
          createdMs: 1_700_000_000_002,
          operation: _groundEdit,
        ),
        _groundHash,
      ),
  ]);
}

final class _Admission implements GroupMlsAdmissionPort {
  const _Admission();

  @override
  Future<Result<BetaMlsAuthenticationInput>> authenticateCurrentGroup({
    required GroupState current,
    required String actorUserId,
    required String actorDeviceId,
  }) async => Result.success(_authentication());

  @override
  Future<Result<GroupMlsControlContext>> prepareControl({
    required GroupState current,
    required GroupControlOperation operation,
    required String actorUserId,
    required String actorDeviceId,
  }) async => Result.success(
    GroupMlsControlContext(
      authentication: _authentication(),
      operation: operation,
      admissions: const [],
    ),
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

BetaMlsAuthenticationInput _authentication() => BetaMlsAuthenticationInput(
  opaqueDeviceState: Uint8List.fromList([1]),
  migrationUnixDay: 20_302,
  localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
);

final class _Ids implements ApplicationProtocolPort {
  var _next = 0xa1;

  @override
  Future<Result<Uint8List>> generateEventId() async =>
      Result.success(Uint8List.fromList(List<int>.filled(16, _next++)));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

/// Signs and verifies as whoever the test says, so a sibling can be authored by
/// a member other than the local device.
final class _Crypto implements BetaMlsCryptoPort {
  String signerUserId = _alice;
  String signerDeviceId = _aliceDevice;
  String signedHash = _createHash;

  final _groupIdBytes = _hexBytes(_groupId);
  final _confirmation = Uint8List.fromList(List<int>.filled(32, 7));

  @override
  Future<Result<BetaMlsSignedControlOutput>> signBetaMlsControl(
    BetaMlsSignControlRequest request,
  ) async => Result.success(_signed(signerUserId, signerDeviceId, signedHash));

  @override
  Future<Result<BetaMlsSignedControlOutput>> verifyBetaMlsControl(
    BetaMlsVerifyControlRequest request,
  ) async => Result.success(
    BetaMlsSignedControlOutput(
      canonicalBytes: Uint8List.fromList([7]),
      signature: Uint8List.fromList(List<int>.filled(64, 8)),
      controlStateHash: _hexBytes(signedHash),
      signedPayload: request.signedPayload,
      signerUserId: request.signerUserId,
      signerDeviceId: request.signerDeviceId,
    ),
  );

  @override
  Future<Result<BetaMlsMessageOutput>> sendBetaMlsApplication(
    BetaMlsSendApplicationRequest request,
  ) async => Result.success(
    BetaMlsMessageOutput(
      sealedGroupState: Uint8List.fromList([12]),
      message: Uint8List.fromList([13]),
      groupId: _groupIdBytes,
      epoch: request.sealedGroupState.single == 20 ? 2 : 1,
      exporterConfirmation: _confirmation,
    ),
  );

  @override
  Future<Result<BetaMlsCommitOutput>> removeBetaMlsMembers(
    BetaMlsRemoveMembersRequest request,
  ) async => Result.success(
    BetaMlsCommitOutput(
      sealedGroupState: Uint8List.fromList([20]),
      commit: Uint8List.fromList([21]),
      commitDigest: Uint8List.fromList(List<int>.filled(32, 0x15)),
      authenticationBundleRequests: [Uint8List.fromList('CPBRV001'.codeUnits)],
      welcomes: const [],
      groupInfo: Uint8List.fromList([22]),
      groupId: _groupIdBytes,
      epoch: 2,
      exporterConfirmation: _confirmation,
    ),
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

BetaMlsSignedControlOutput _signed(String user, String device, String hash) =>
    BetaMlsSignedControlOutput(
      canonicalBytes: Uint8List.fromList([7]),
      signature: Uint8List.fromList(List<int>.filled(64, 8)),
      controlStateHash: _hexBytes(hash),
      signedPayload: Uint8List.fromList('CPGCV001'.codeUnits),
      signerUserId: _hexBytes(user.replaceAll('-', '')),
      signerDeviceId: _hexBytes(device.replaceAll('-', '')),
    );

Uint8List _hexBytes(String value) => Uint8List.fromList([
  for (var index = 0; index + 1 < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);
