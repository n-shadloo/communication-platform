import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/application/ports/beta_mls_crypto_port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/native_beta_group_mls.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = '10000000-0000-4000-8000-000000000001';
const _aliceDevice = '20000000-0000-4000-8000-000000000001';
const _bob = '30000000-0000-4000-8000-000000000001';
const _bobDevice = '40000000-0000-4000-8000-000000000001';
const _charlie = '50000000-0000-4000-8000-000000000001';
const _charlieDevice = '60000000-0000-4000-8000-000000000001';

void main() {
  test(
    'prepares one real create transaction from Commit through signed control',
    () async {
      final crypto = _Crypto();
      final result = await NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: const _ApplicationProtocol(),
      ).prepareCreate(_intent());

      expect(result, isA<Success<PreparedGroupTransition>>());
      final prepared = (result as Success<PreparedGroupTransition>).value;
      expect(prepared.newOpaqueMlsState, [12]);
      expect(prepared.mlsObject.sublist(0, 8), 'CPGTO001'.codeUnits);
      expect(prepared.signedControl.event.mlsEpoch, 1);
      expect(
        prepared.signedControl.event.mlsCommitHash,
        _hex(List<int>.filled(32, 3)),
      );
      expect(
        prepared.signedControl.controlStateHash,
        _hex(List<int>.filled(32, 9)),
      );
      expect(prepared.signedControl.signature, List<int>.filled(64, 8));
      expect(crypto.calls, ['create', 'sign', 'send']);
      final probe = await NativeBetaGroupMls(
        crypto,
      ).probeIncomingTransport(prepared.mlsObject);
      expect(
        (probe as Success<GroupMlsTransportProbe>).value.kind,
        GroupMlsTransportKind.welcome,
      );

      final applied = const GroupControlStateMachine().apply(
        previous: null,
        signedControl: prepared.signedControl,
        localUserId: _alice,
      );
      expect(applied, isA<GroupControlAccepted>());
      expect((applied as GroupControlAccepted).state.acceptedEpoch, 1);
    },
  );

  test(
    'prepares a signed metadata control without an MLS epoch change',
    () async {
      final crypto = _Crypto();
      final current = GroupState(
        groupId: _hex(List<int>.filled(32, 6)),
        metadata: const GroupMetadata(name: 'Before'),
        invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
        historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
        members: _intent().members,
        controlRevision: 1,
        controlStateHash: _hex(List<int>.filled(32, 0xb)),
        acceptedEpoch: 1,
      );
      final result =
          await NativeBetaGroupMls(
            crypto,
            admission: const _Admission(),
            applicationProtocol: const _ApplicationProtocol(),
          ).prepareControl(
            current: current,
            currentOpaqueMlsState: Uint8List.fromList([1]),
            operation: const UpdateGroupMetadataOperation(
              GroupMetadata(name: 'After'),
            ),
            actorUserId: _alice,
            actorDeviceId: _aliceDevice,
            createdMs: 1_700_000_000_001,
          );

      expect(result, isA<Success<PreparedGroupTransition>>());
      final prepared = (result as Success<PreparedGroupTransition>).value;
      expect(prepared.signedControl.event.mlsEpoch, 1);
      expect(prepared.signedControl.event.mlsCommitHash, isNull);
      expect(prepared.recipientUserIds.toSet(), {_alice, _bob});
      expect(prepared.mlsObject.sublist(0, 8), 'CPGTO001'.codeUnits);
      expect(prepared.mlsObject[10], 2);
      expect(crypto.calls, ['sign', 'send']);
      final probe = await NativeBetaGroupMls(
        crypto,
      ).probeIncomingTransport(prepared.mlsObject);
      expect(
        (probe as Success<GroupMlsTransportProbe>).value.kind,
        GroupMlsTransportKind.control,
      );
      final applied = const GroupControlStateMachine().apply(
        previous: current,
        signedControl: prepared.signedControl,
        localUserId: _alice,
      );
      expect(applied, isA<GroupControlAccepted>());
      expect((applied as GroupControlAccepted).state.metadata.name, 'After');
    },
  );

  test('binds an invited member to an MLS add Commit and Welcome', () async {
    final crypto = _Crypto();
    final current = _currentGroup();
    final result =
        await NativeBetaGroupMls(
          crypto,
          admission: const _Admission(),
          applicationProtocol: const _ApplicationProtocol(),
          transcript: const _Transcript(),
        ).prepareControl(
          current: current,
          currentOpaqueMlsState: Uint8List.fromList([1]),
          operation: InviteGroupMembersOperation([
            GroupMember(
              userId: _charlie,
              displayName: 'Charlie',
              role: GroupRole.member,
              verified: true,
              deviceIds: const [_charlieDevice],
            ),
          ]),
          actorUserId: _alice,
          actorDeviceId: _aliceDevice,
          createdMs: 1_700_000_000_004,
        );

    expect(result, isA<Success<PreparedGroupTransition>>());
    final prepared = (result as Success<PreparedGroupTransition>).value;
    expect(prepared.signedControl.event.mlsEpoch, 2);
    expect(
      prepared.signedControl.event.mlsCommitHash,
      _hex(List.filled(32, 17)),
    );
    expect(prepared.recipientUserIds.toSet(), {_alice, _bob, _charlie});
    expect(crypto.calls, ['verify', 'add', 'sign', 'send']);
  });

  test('binds member removal to an MLS remove Commit', () async {
    final crypto = _Crypto();
    final result =
        await NativeBetaGroupMls(
          crypto,
          admission: const _Admission(),
          applicationProtocol: const _ApplicationProtocol(),
        ).prepareControl(
          current: _currentGroup(),
          currentOpaqueMlsState: Uint8List.fromList([1]),
          operation: const RemoveGroupMemberOperation(_bob),
          actorUserId: _alice,
          actorDeviceId: _aliceDevice,
          createdMs: 1_700_000_000_005,
        );

    expect(result, isA<Success<PreparedGroupTransition>>());
    final prepared = (result as Success<PreparedGroupTransition>).value;
    expect(prepared.signedControl.event.mlsEpoch, 2);
    expect(
      prepared.signedControl.event.mlsCommitHash,
      _hex(List.filled(32, 21)),
    );
    expect(prepared.recipientUserIds.toSet(), {_alice, _bob});
    expect(crypto.calls, ['remove', 'sign', 'send']);
  });

  test('encodes a real application event before MLS encryption', () async {
    final crypto = _Crypto();
    final current = GroupState(
      groupId: _hex(List<int>.filled(32, 6)),
      metadata: const GroupMetadata(name: 'Beta group'),
      invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
      historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
      members: _intent().members,
      controlRevision: 1,
      controlStateHash: _hex(List<int>.filled(32, 0xb)),
      acceptedEpoch: 1,
    );
    final result =
        await NativeBetaGroupMls(
          crypto,
          admission: const _Admission(),
          applicationProtocol: const _ApplicationProtocol(),
          applicationIdentity: const _ApplicationIdentity(),
        ).prepareApplicationMessage(
          current: current,
          currentOpaqueMlsState: Uint8List.fromList([1]),
          senderUserId: _alice,
          senderDeviceId: _aliceDevice,
          text: 'hello beta group',
          createdMs: 1_700_000_000_002,
        );

    expect(result, isA<Success<PreparedGroupMessage>>());
    final prepared = (result as Success<PreparedGroupMessage>).value;
    expect(prepared.messageId, _hex(List<int>.filled(16, 0xa1)));
    expect(prepared.mlsObject.sublist(0, 8), 'CPGTO001'.codeUnits);
    expect(prepared.mlsObject[10], 3);
    expect(crypto.sendRequest!.applicationData, [0x99]);
    expect(crypto.sendRequest!.authenticatedData, List<int>.filled(16, 0xa1));
    expect(prepared.recipientUserIds.toSet(), {_alice, _bob});
    final probe = await NativeBetaGroupMls(
      crypto,
    ).probeIncomingTransport(prepared.mlsObject);
    expect(
      (probe as Success<GroupMlsTransportProbe>).value.kind,
      GroupMlsTransportKind.application,
    );
  });

  test('authenticates and decodes an incoming MLS application event', () async {
    final crypto = _Crypto();
    final current = GroupState(
      groupId: _hex(List<int>.filled(32, 6)),
      metadata: const GroupMetadata(name: 'Beta group'),
      invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
      historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
      members: _intent().members,
      controlRevision: 1,
      controlStateHash: _hex(List<int>.filled(32, 0xb)),
      acceptedEpoch: 1,
    );
    final adapter = NativeBetaGroupMls(
      crypto,
      admission: const _Admission(),
      applicationProtocol: const _ApplicationProtocol(),
      applicationIdentity: const _ApplicationIdentity(),
    );
    final outbound = await adapter.prepareApplicationMessage(
      current: current,
      currentOpaqueMlsState: Uint8List.fromList([1]),
      senderUserId: _alice,
      senderDeviceId: _aliceDevice,
      text: 'hello beta group',
      createdMs: 1_700_000_000_002,
    );
    final object = (outbound as Success<PreparedGroupMessage>).value.mlsObject;
    crypto.calls.clear();

    final incoming = await adapter.inspectIncomingApplication(
      current: current,
      currentOpaqueMlsState: Uint8List.fromList([1]),
      mlsObject: object,
      localUserId: _bob,
      localDeviceId: _bobDevice,
    );

    expect(incoming, isA<Success<PreparedGroupMessage>>());
    final prepared = (incoming as Success<PreparedGroupMessage>).value;
    expect(prepared.outbound, isFalse);
    expect(prepared.messageId, _hex(List<int>.filled(16, 0xa1)));
    expect(prepared.senderUserId, _alice);
    expect(prepared.senderDeviceId, _aliceDevice);
    expect(prepared.text, 'hello beta group');
    expect(prepared.newOpaqueMlsState, [20]);
    expect(prepared.recipientUserIds, isEmpty);
    expect(crypto.calls, ['process']);
  });

  test('authenticates an incoming control sender and signed payload', () async {
    final crypto = _Crypto();
    final current = GroupState(
      groupId: _hex(List<int>.filled(32, 6)),
      metadata: const GroupMetadata(name: 'Before'),
      invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
      historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
      members: _intent().members,
      controlRevision: 1,
      controlStateHash: _hex(List<int>.filled(32, 0xb)),
      acceptedEpoch: 1,
    );
    final adapter = NativeBetaGroupMls(
      crypto,
      admission: const _Admission(),
      applicationProtocol: const _ApplicationProtocol(),
    );
    final outbound = await adapter.prepareControl(
      current: current,
      currentOpaqueMlsState: Uint8List.fromList([1]),
      operation: const UpdateGroupMetadataOperation(
        GroupMetadata(name: 'After'),
      ),
      actorUserId: _alice,
      actorDeviceId: _aliceDevice,
      createdMs: 1_700_000_000_003,
    );
    final object =
        (outbound as Success<PreparedGroupTransition>).value.mlsObject;
    crypto.calls.clear();

    final incoming = await adapter.inspectIncomingControl(
      current: current,
      currentOpaqueMlsState: Uint8List.fromList([1]),
      mlsObject: object,
      localUserId: _bob,
      localDeviceId: _bobDevice,
    );

    expect(incoming, isA<Success<PreparedGroupTransition>>());
    final prepared = (incoming as Success<PreparedGroupTransition>).value;
    expect(prepared.outbound, isFalse);
    expect(prepared.newOpaqueMlsState, [20]);
    expect(
      prepared.signedControl.event.operation,
      isA<UpdateGroupMetadataOperation>(),
    );
    expect(crypto.calls, ['process', 'verify']);
  });

  test('joins a Welcome and returns atomic KeyPackage consumption', () async {
    final crypto = _Crypto();
    final adapter = NativeBetaGroupMls(
      crypto,
      admission: const _Admission(),
      applicationProtocol: const _ApplicationProtocol(),
    );
    final created = await adapter.prepareCreate(_intent());
    final object =
        (created as Success<PreparedGroupTransition>).value.mlsObject;
    crypto.calls.clear();

    final joined = await adapter.inspectIncomingWelcome(
      mlsObject: object,
      localUserId: _bob,
      localDeviceId: _bobDevice,
    );

    expect(joined, isA<Success<PreparedGroupTransition>>());
    final prepared = (joined as Success<PreparedGroupTransition>).value;
    expect(prepared.outbound, isFalse);
    expect(prepared.newOpaqueMlsState, [20]);
    expect(prepared.consumedKeyPackageState!.deviceId, _bobDevice);
    expect(prepared.consumedKeyPackageState!.expectedStateRevision, 4);
    expect(prepared.consumedKeyPackageState!.nextSealedState, [41]);
    expect(crypto.calls, ['join', 'process', 'verify']);
  });

  test(
    'joins a later-member Welcome only after verifying the full control chain',
    () async {
      final crypto = _Crypto();
      final adapter = NativeBetaGroupMls(
        crypto,
        admission: const _Admission(),
        applicationProtocol: const _ApplicationProtocol(),
        transcript: const _Transcript(),
      );
      final outgoing = await adapter.prepareControl(
        current: _currentGroup(),
        currentOpaqueMlsState: Uint8List.fromList([1]),
        operation: InviteGroupMembersOperation([
          GroupMember(
            userId: _charlie,
            displayName: 'Charlie',
            role: GroupRole.member,
            verified: true,
            deviceIds: const [_charlieDevice],
          ),
        ]),
        actorUserId: _alice,
        actorDeviceId: _aliceDevice,
        createdMs: 1_700_000_000_006,
      );
      final object =
          (outgoing as Success<PreparedGroupTransition>).value.mlsObject;
      crypto.calls.clear();

      final incoming = await adapter.inspectIncomingWelcome(
        mlsObject: object,
        localUserId: _charlie,
        localDeviceId: _charlieDevice,
      );

      expect(incoming, isA<Success<PreparedGroupTransition>>());
      final prepared = (incoming as Success<PreparedGroupTransition>).value;
      expect(prepared.signedControl.event.revision, 2);
      expect(prepared.signedControl.event.mlsEpoch, 2);
      expect(prepared.precedingControlTranscript, hasLength(1));
      expect(prepared.controlTranscriptEntry, isNotNull);
      expect(prepared.consumedKeyPackageState!.deviceId, _charlieDevice);
      expect(crypto.calls, ['verify', 'join', 'process', 'verify']);
    },
  );
}

GroupCreationIntent _intent() => GroupCreationIntent(
  creatorUserId: _alice,
  creatorDeviceId: _aliceDevice,
  metadata: const GroupMetadata(name: 'Beta group'),
  members: [
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
      role: GroupRole.member,
      verified: true,
      deviceIds: const [_bobDevice],
    ),
  ],
  createdMs: 1_700_000_000_000,
);

GroupState _currentGroup() => GroupState(
  groupId: _hex(List<int>.filled(32, 6)),
  metadata: const GroupMetadata(name: 'Before'),
  invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
  historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
  members: _intent().members,
  controlRevision: 1,
  controlStateHash: _hex(List<int>.filled(32, 9)),
  acceptedEpoch: 1,
);

final class _Admission implements GroupMlsAdmissionPort {
  const _Admission();

  @override
  Future<Result<BetaMlsAuthenticationInput>> authenticateCurrentGroup({
    required GroupState current,
    required String actorUserId,
    required String actorDeviceId,
  }) async => Result.success(_authentication());

  @override
  Future<Result<GroupMlsJoinContext>> prepareJoin({
    required String localUserId,
    required String localDeviceId,
  }) async => Result.success(
    GroupMlsJoinContext(
      authentication: _authentication(),
      sealedKeyPackageState: Uint8List.fromList([30]),
      keyPackageStateRevision: 4,
    ),
  );

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
      admissions: operation is InviteGroupMembersOperation
          ? [
              GroupMlsClaimedAdmission(
                userId: _charlie,
                deviceId: _charlieDevice,
                wrappedKeyPackage: Uint8List(4096),
              ),
            ]
          : const [],
    ),
  );

  @override
  Future<Result<GroupMlsCreationContext>> prepareCreate(
    GroupCreationIntent intent,
  ) async => Result.success(
    GroupMlsCreationContext(
      authentication: BetaMlsAuthenticationInput(
        opaqueDeviceState: Uint8List.fromList([1]),
        migrationUnixDay: 20_302,
        localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
        additionalVerifiedBundleRequests: [
          Uint8List.fromList('CPBRV001|bob'.codeUnits),
        ],
      ),
      authenticatedMembers: intent.members,
      admissions: [
        GroupMlsClaimedAdmission(
          userId: _bob,
          deviceId: _bobDevice,
          wrappedKeyPackage: Uint8List(4096),
        ),
      ],
    ),
  );
}

final class _Transcript implements GroupControlTranscriptPort {
  const _Transcript();

  @override
  Future<Result<List<GroupControlTranscriptEntry>>> readVerifiedTranscript(
    String groupId,
  ) async {
    final event = GroupControlEvent(
      eventId: _hex(List<int>.filled(16, 0x31)),
      groupId: groupId,
      revision: 1,
      previousControlStateHash: null,
      mlsEpoch: 1,
      mlsCommitHash: _hex(List<int>.filled(32, 3)),
      signerUserId: _alice,
      signerDeviceId: _aliceDevice,
      createdMs: 1_700_000_000_000,
      operation: CreateGroupOperation(
        metadata: const GroupMetadata(name: 'Before'),
        invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
        historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
        initialMembers: _intent().members,
      ),
    );
    return Result.success([
      GroupControlTranscriptEntry(
        signedControl: SignedGroupControlEvent(
          event: event,
          controlStateHash: _hex(List<int>.filled(32, 9)),
          canonicalBytes: Uint8List.fromList([7]),
          signature: Uint8List.fromList(List<int>.filled(64, 8)),
        ),
        signedPayload: Uint8List.fromList('CPGCV001'.codeUnits),
        signerAuthenticationProof: Uint8List.fromList('CPBRV001'.codeUnits),
      ),
    ]);
  }
}

BetaMlsAuthenticationInput _authentication() => BetaMlsAuthenticationInput(
  opaqueDeviceState: Uint8List.fromList([1]),
  migrationUnixDay: 20_302,
  localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
);

final class _Crypto implements BetaMlsCryptoPort {
  final calls = <String>[];
  BetaMlsSendApplicationRequest? sendRequest;
  final groupId = Uint8List.fromList(List<int>.filled(32, 6));
  final confirmation = Uint8List.fromList(List<int>.filled(32, 7));

  @override
  Future<Result<BetaMlsCommitOutput>> createBetaMlsGroup(
    BetaMlsCreateRequest request,
  ) async {
    calls.add('create');
    return Result.success(
      BetaMlsCommitOutput(
        sealedGroupState: Uint8List.fromList([1]),
        commit: Uint8List.fromList([2]),
        commitDigest: Uint8List.fromList(List<int>.filled(32, 3)),
        authenticationBundleRequests: [
          Uint8List.fromList('CPBRV001'.codeUnits),
        ],
        welcomes: [
          Uint8List.fromList([4]),
        ],
        groupInfo: Uint8List.fromList([5]),
        groupId: groupId,
        epoch: 1,
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<BetaMlsSignedControlOutput>> signBetaMlsControl(
    BetaMlsSignControlRequest request,
  ) async {
    calls.add('sign');
    return Result.success(
      BetaMlsSignedControlOutput(
        canonicalBytes: Uint8List.fromList([7]),
        signature: Uint8List.fromList(List<int>.filled(64, 8)),
        controlStateHash: Uint8List.fromList(List<int>.filled(32, 9)),
        signedPayload: Uint8List.fromList('CPGCV001'.codeUnits),
        signerUserId: _uuidBytes(_alice),
        signerDeviceId: _uuidBytes(_aliceDevice),
      ),
    );
  }

  @override
  Future<Result<BetaMlsMessageOutput>> sendBetaMlsApplication(
    BetaMlsSendApplicationRequest request,
  ) async {
    calls.add('send');
    sendRequest = request;
    final membershipEpoch =
        request.sealedGroupState.length == 1 &&
        (request.sealedGroupState.single == 15 ||
            request.sealedGroupState.single == 20);
    return Result.success(
      BetaMlsMessageOutput(
        sealedGroupState: Uint8List.fromList([12]),
        message: Uint8List.fromList(
          request.applicationData.length == 1 &&
                  request.applicationData.single == 0x99
              ? [14]
              : [13],
        ),
        groupId: groupId,
        epoch: membershipEpoch ? 2 : 1,
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<BetaMlsCommitOutput>> addBetaMlsMembers(
    BetaMlsAddMembersRequest request,
  ) async {
    calls.add('add');
    return Result.success(
      BetaMlsCommitOutput(
        sealedGroupState: Uint8List.fromList([15]),
        commit: Uint8List.fromList([16]),
        commitDigest: Uint8List.fromList(List<int>.filled(32, 17)),
        authenticationBundleRequests: [
          Uint8List.fromList('CPBRV001|charlie'.codeUnits),
        ],
        welcomes: [
          Uint8List.fromList([18]),
        ],
        groupInfo: Uint8List.fromList([19]),
        groupId: groupId,
        epoch: 2,
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<BetaMlsCommitOutput>> commitBetaMlsPendingProposals(
    BetaMlsPendingCommitRequest request,
  ) async => throw UnimplementedError();
  @override
  Future<Result<GeneratedMlsKeyPackages>> generateBetaMlsKeyPackages(
    MlsKeyPackageGenerationRequest request,
  ) async => throw UnimplementedError();
  @override
  Future<Result<BetaMlsJoinOutput>> joinBetaMlsGroup(
    BetaMlsJoinRequest request,
  ) async {
    calls.add('join');
    final isLaterInvite =
        request.welcome.length == 1 && request.welcome[0] == 18;
    return Result.success(
      BetaMlsJoinOutput(
        sealedGroupState: Uint8List.fromList([isLaterInvite ? 42 : 40]),
        sealedKeyPackageState: Uint8List.fromList([41]),
        groupId: groupId,
        epoch: isLaterInvite ? 2 : 1,
        roster: [
          BetaMlsRosterDevice(
            userId: _uuidBytes(_alice),
            deviceId: _uuidBytes(_aliceDevice),
          ),
          BetaMlsRosterDevice(
            userId: _uuidBytes(_bob),
            deviceId: _uuidBytes(_bobDevice),
          ),
          if (isLaterInvite)
            BetaMlsRosterDevice(
              userId: _uuidBytes(_charlie),
              deviceId: _uuidBytes(_charlieDevice),
            ),
        ],
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<Uint8List>> hashBetaMlsObject(
    BetaMlsHashObjectRequest request,
  ) async => Result.success(
    Uint8List.fromList(
      List<int>.filled(
        32,
        request.object.length == 1 && request.object[0] == 16 ? 17 : 3,
      ),
    ),
  );
  @override
  Future<Result<BetaMlsProcessedMessage>> processBetaMlsMessage(
    BetaMlsProcessMessageRequest request,
  ) async {
    calls.add('process');
    final isApplicationEvent =
        request.message.length == 1 && request.message.single == 14;
    final isLaterInvite =
        request.sealedGroupState.length == 1 &&
        request.sealedGroupState.single == 42;
    return Result.success(
      BetaMlsProcessedMessage(
        sealedGroupState: Uint8List.fromList([20]),
        messageDigest: Uint8List(32),
        kind: BetaMlsReceivedKind.application,
        senderLeafIndex: 0,
        senderUserId: _uuidBytes(_alice),
        senderDeviceId: _uuidBytes(_aliceDevice),
        data: Uint8List.fromList(
          isApplicationEvent ? [0x99] : 'CPGCV001'.codeUnits,
        ),
        authenticatedData: Uint8List.fromList(List<int>.filled(16, 0xa1)),
        groupId: groupId,
        epoch: isLaterInvite ? 2 : 1,
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<BetaMlsMessageOutput>> proposeBetaMlsUpdate(
    BetaMlsPendingCommitRequest request,
  ) async => throw UnimplementedError();
  @override
  Future<Result<BetaMlsCommitOutput>> removeBetaMlsMembers(
    BetaMlsRemoveMembersRequest request,
  ) async {
    calls.add('remove');
    return Result.success(
      BetaMlsCommitOutput(
        sealedGroupState: Uint8List.fromList([20]),
        commit: Uint8List.fromList([21]),
        commitDigest: Uint8List.fromList(List<int>.filled(32, 21)),
        authenticationBundleRequests: [
          Uint8List.fromList('CPBRV001'.codeUnits),
        ],
        welcomes: const [],
        groupInfo: Uint8List.fromList([22]),
        groupId: groupId,
        epoch: 2,
        exporterConfirmation: confirmation,
      ),
    );
  }

  @override
  Future<Result<BetaMlsSignedControlOutput>> verifyBetaMlsControl(
    BetaMlsVerifyControlRequest request,
  ) async {
    calls.add('verify');
    return Result.success(
      BetaMlsSignedControlOutput(
        canonicalBytes: Uint8List.fromList([7]),
        signature: Uint8List.fromList(List<int>.filled(64, 8)),
        controlStateHash: Uint8List.fromList(List<int>.filled(32, 9)),
        signedPayload: Uint8List.fromList('CPGCV001'.codeUnits),
        signerUserId: _uuidBytes(_alice),
        signerDeviceId: _uuidBytes(_aliceDevice),
      ),
    );
  }
}

final class _ApplicationProtocol implements ApplicationProtocolPort {
  const _ApplicationProtocol();

  @override
  Future<Result<Uint8List>> generateEventId() async =>
      Result.success(Uint8List.fromList(List<int>.filled(16, 0xa1)));

  @override
  Future<Result<DecodedApplicationEvent>> decode(Uint8List bytes) async =>
      Result.success(
        SupportedApplicationEvent(
          event: ApplicationEventRecord(
            version: ApplicationMessageProtocolV1.version,
            eventId: Uint8List.fromList(List<int>.filled(16, 0xa1)),
            conversationId: Uint8List.fromList(List<int>.filled(32, 6)),
            kindValue: ApplicationEventKind.messageCreate.wireValue,
            senderUserId: _uuidBytes(_alice),
            senderDeviceId: _uuidBytes(_aliceDevice),
            senderCounter: 7,
            createdMs: 1_700_000_000_002,
            references: const [],
            body: MessageCreateBody(
              messageId: Uint8List.fromList(List<int>.filled(16, 0xa1)),
              text: 'hello beta group',
            ),
          ),
          canonicalBytes: bytes,
        ),
      );
  @override
  Future<Result<Uint8List>> deriveDirectConversationId({
    required Uint8List firstUserId,
    required Uint8List secondUserId,
  }) async => throw UnimplementedError();
  @override
  Future<Result<Uint8List>> deriveSavedConversationId(Uint8List userId) async =>
      throw UnimplementedError();
  @override
  Future<Result<Uint8List>> encode(ApplicationEventRecord event) async =>
      Result.success(Uint8List.fromList([0x99]));
}

final class _ApplicationIdentity implements GroupApplicationIdentityPort {
  const _ApplicationIdentity();

  @override
  Future<Result<int>> reserveSenderCounter(String deviceId) async =>
      const Result.success(7);
}

Uint8List _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  return Uint8List.fromList([
    for (var index = 0; index < compact.length; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}

String _hex(List<int> value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
