import 'dart:typed_data';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:drift/drift.dart';

const localUserId = '00000000-0000-0000-0000-000000000001';
const localDeviceId = '00000000-0000-0000-0000-000000000011';
const peerUserId = '00000000-0000-0000-0000-000000000002';
const peerDeviceId = '00000000-0000-0000-0000-000000000022';

/// Deterministic bytes of [length], seeded by [seed].
Uint8List seededBytes(int seed, int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (seed + i) & 0xff));

/// A locally originated message create, ready to echo.
ApplicationEventCommit localMessageCommit({
  required int seed,
  required int counter,
  String text = 'hello',
}) {
  final event = ApplicationEventRecord(
    version: ApplicationMessageProtocolV1.version,
    eventId: seededBytes(seed, 16),
    conversationId: seededBytes(9, 32),
    kindValue: ApplicationEventKind.messageCreate.wireValue,
    senderUserId: protocolUuidBytes(localUserId),
    senderDeviceId: protocolUuidBytes(localDeviceId),
    senderCounter: counter,
    createdMs: 1700000000000 + seed,
    references: const [],
    body: MessageCreateBody(messageId: seededBytes(seed, 16), text: text),
  );
  return ApplicationEventCommit(
    event: event,
    canonicalBytes: seededBytes(seed, 96),
    currentUserId: localUserId,
    currentDeviceId: localDeviceId,
    conversationKind: ConversationKind.direct.index,
    peerUserId: peerUserId,
    localOrigin: true,
    authenticatedAt: DateTime.fromMillisecondsSinceEpoch(
      1700000100000,
      isUtc: true,
    ),
  );
}

/// A reaction from the peer, which forces exactly one conversation rebuild.
///
/// It exists so a test can measure what a full projection of this conversation
/// costs, which is what an outbox attempt transition used to do.
ApplicationEventCommit peerReactionCommit({
  required int seed,
  required int counter,
  required Uint8List targetMessageId,
}) {
  final event = ApplicationEventRecord(
    version: ApplicationMessageProtocolV1.version,
    eventId: seededBytes(seed, 16),
    conversationId: seededBytes(9, 32),
    kindValue: ApplicationEventKind.reactionSet.wireValue,
    senderUserId: protocolUuidBytes(peerUserId),
    senderDeviceId: protocolUuidBytes(peerDeviceId),
    senderCounter: counter,
    createdMs: 1700000000000 + seed,
    references: [targetMessageId],
    body: ReactionSetBody(targetMessageId: targetMessageId, emoji: '\u{1F44D}'),
  );
  return ApplicationEventCommit(
    event: event,
    canonicalBytes: seededBytes(seed, 96),
    currentUserId: localUserId,
    currentDeviceId: localDeviceId,
    conversationKind: ConversationKind.direct.index,
    peerUserId: peerUserId,
    localOrigin: false,
    authenticatedAt: DateTime.fromMillisecondsSinceEpoch(
      1700000100000,
      isUtc: true,
    ),
  );
}

/// The sealed per-recipient commit the fan-out produces for [commit].
PairwiseSendCommit sealedSendFor(
  ApplicationEventCommit commit, {
  int stateVersion = 1,
  int targets = 1,
}) {
  final eventId = protocolBytesToHex(commit.event.eventId);
  return PairwiseSendCommit(
    operationId: 'application:$eventId',
    eventId: eventId,
    currentDeviceId: localDeviceId,
    expectedDeviceStateVersion: stateVersion,
    openedLocalPayload: commit.canonicalBytes,
    targets: [
      for (var index = 0; index < targets; index += 1)
        PreparedPairwiseSendTarget(
          recipientUserId: peerUserId,
          recipientDeviceId:
              '00000000-0000-0000-0000-0000000000${(0x22 + index).toRadixString(16).padLeft(2, '0')}',
          exactCiphertext: Uint8List(1024),
          sessionTransition: PairwiseSessionTransition(
            localDeviceId: localDeviceId,
            remoteUserId: peerUserId,
            remoteDeviceId:
                '00000000-0000-0000-0000-0000000000${(0x22 + index).toRadixString(16).padLeft(2, '0')}',
            sessionId: seededBytes(index + 1, 16),
            nextOpaqueState: seededBytes(index + 2, 32),
            expectedStateVersion: null,
            nextStateVersion: 1,
            nextSkippedKeyCount: 0,
            disposition: PairwiseSessionDisposition.primaryBidirectional,
            repairState: PairwiseRepairState.ready,
          ),
        ),
    ],
  );
}

/// The device-key-state row every prepared send is checked against.
Future<void> seedDeviceState(LocalDatabase database) => database
    .into(database.secureSecrets)
    .insert(
      SecureSecretsCompanion.insert(
        secretId: 'current-device-key-state-v1',
        kind: 0,
        wrappedCiphertextOrOpaqueHandle: seededBytes(1, 8),
        formatVersion: 2,
      ),
    );
