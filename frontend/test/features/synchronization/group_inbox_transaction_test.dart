import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/pairwise_sync_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/group_use_cases.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/development_in_memory_group_mls.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '10000000-0000-4000-8000-000000000001';
const _ownerDevice = '20000000-0000-4000-8000-000000000001';
const _member = '30000000-0000-4000-8000-000000000001';
const _memberDevice = '40000000-0000-4000-8000-000000000001';
const _envelope = '50000000-0000-4000-8000-000000000001';

void main() {
  late LocalDatabase database;
  late DriftGroupRepository groups;
  late DriftSyncStore sync;
  late GroupState group;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    groups = DriftGroupRepository(database);
    sync = DriftSyncStore(database);
    await _insertUser(database, _owner);
    await _insertUser(database, _member);
    final created =
        await CreateGroup(
          repository: groups,
          crypto: DevelopmentInMemoryGroupMls.forTests(seed: 190),
          clock: const _Clock(),
          developmentPreviewOnly: true,
        )(
          currentUserId: _owner,
          currentDeviceId: _ownerDevice,
          ownerDisplayName: 'Owner',
          metadata: const GroupMetadata(name: 'Atomic inbox'),
          selectedMembers: [
            GroupMember(
              userId: _member,
              displayName: 'Member',
              role: GroupRole.member,
              deviceIds: const [_memberDevice],
            ),
          ],
        );
    group = (created as Success<GroupState>).value;
    await database.delete(database.groupOutboundObjects).go();
    await sync.persistDrainPage(
      DrainPage(
        envelopes: [
          SyncEnvelope(
            id: _envelope,
            sequence: 1,
            exactCiphertext: Uint8List(1024),
          ),
        ],
        hasMore: false,
        prunedThrough: 0,
      ),
    );
    await sync.beginNextEnvelopeInspection(now: const _Clock().now());
  });

  tearDown(() => database.close());

  test('pairwise and MLS application states commit together', () async {
    const messageId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final prepared = _preparedMessage(
      group,
      messageId: messageId,
      stateByte: 91,
    );
    final result = await sync.commitOpaqueInspection(
      envelopeId: _envelope,
      inspection: _inspection(
        PreparedGroupInboxMessage(expectedGroup: group, prepared: prepared),
      ),
    );

    expect(result, isA<Success<bool>>());
    expect(
      await database.select(database.pairwiseSessions).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.pairwiseReplayMarkers).get(),
      hasLength(1),
    );
    final message = await database.select(database.messages).getSingle();
    expect(message.messageId, messageId);
    expect(message.status, MessageTransportState.received.index);
    expect(
      (await groups.readOpaqueMlsState(group.groupId) as Success<Uint8List?>)
          .value,
      [91],
    );
    expect(await database.select(database.groupOutboundObjects).get(), isEmpty);
    expect(
      (await database.select(database.inboxEnvelopes).getSingle())
          .dependencyClass,
      EnvelopeDependency.potentiallyMls.index,
    );
  });

  test('MLS CAS failure rolls back the pairwise receive', () async {
    const messageId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    final stale = group.copyWith(
      controlStateHash:
          '0000000000000000000000000000000000000000000000000000000000000000',
    );
    final prepared = _preparedMessage(
      group,
      messageId: messageId,
      stateByte: 92,
    );

    final result = await sync.commitOpaqueInspection(
      envelopeId: _envelope,
      inspection: _inspection(
        PreparedGroupInboxMessage(expectedGroup: stale, prepared: prepared),
      ),
    );

    expect(result, isA<FailureResult<bool>>());
    expect(await database.select(database.pairwiseSessions).get(), isEmpty);
    expect(
      await database.select(database.pairwiseReplayMarkers).get(),
      isEmpty,
    );
    expect(await database.select(database.messages).get(), isEmpty);
    expect(
      (await database.select(database.inboxEnvelopes).getSingle())
          .processingState,
      InboxProcessingState.inspecting.index,
    );
  });
}

PreparedGroupMessage _preparedMessage(
  GroupState group, {
  required String messageId,
  required int stateByte,
}) => PreparedGroupMessage(
  groupId: group.groupId,
  messageId: messageId,
  senderUserId: _member,
  senderDeviceId: _memberDevice,
  text: 'atomic group message',
  createdMs: 1_700_000_000_010,
  epoch: group.acceptedEpoch,
  newOpaqueMlsState: Uint8List.fromList([stateByte]),
  mlsObject: Uint8List.fromList('CPGTO001'.codeUnits),
  operationId: 'beta-group-inbound-message-$messageId',
  recipientUserIds: const [],
  outbound: false,
);

OpaqueEnvelopeInspection _inspection(PreparedGroupInboxCommit groupCommit) =>
    OpaqueEnvelopeInspection(
      opaqueEventId: groupCommit.opaqueEventId,
      dependency: EnvelopeDependency.potentiallyMls,
      groupCommit: groupCommit,
      pairwiseCommit: PairwiseSyncReceiveCommit(
        envelopeId: _envelope,
        opaqueEventId: groupCommit.opaqueEventId,
        senderUserId: _member,
        senderDeviceId: _memberDevice,
        replayMarker: Uint8List(32),
        openedOpaquePayload: Uint8List.fromList('CPGTO001'.codeUnits),
        sessionTransition: PairwiseSyncSessionTransition(
          localDeviceId: _ownerDevice,
          remoteUserId: _member,
          remoteDeviceId: _memberDevice,
          sessionId: Uint8List(16),
          nextOpaqueState: Uint8List.fromList([81]),
          expectedStateVersion: null,
          nextStateVersion: 1,
          nextSkippedKeyCount: 0,
          disposition: PairwiseSessionDisposition.primaryBidirectional.index,
          repairState: PairwiseRepairState.ready.index,
        ),
      ),
    );

Future<void> _insertUser(LocalDatabase database, String userId) => database
    .into(database.users)
    .insert(
      UsersCompanion.insert(
        userId: userId,
        activated: true,
        directoryEntryCiphertext: Uint8List.fromList([1]),
        localState: 0,
      ),
    );

final class _Clock implements TimeSource {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 8, 9, 12);
}
