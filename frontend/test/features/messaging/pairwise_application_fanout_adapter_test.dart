import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/infrastructure/pairwise_application_fanout_adapter.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_transport_store.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentUserId = '10000000-0000-4000-8000-000000000001';
const _currentDeviceId = '10000000-0000-4000-8000-000000000002';
const _peerUserId = '10000000-0000-4000-8000-000000000003';
const _peerDeviceId = '10000000-0000-4000-8000-000000000004';

void main() {
  test('successful ordinary fanout schedules encrypted head gossip', () async {
    final eventId = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final eventIdHex = protocolBytesToHex(eventId);
    final payload = Uint8List.fromList([1, 2, 3]);
    final operation = DurablePairwiseOperation(
      operationId: 'application:$eventIdHex',
      eventId: eventIdHex,
      currentDeviceId: _currentDeviceId,
      openedLocalPayload: payload,
      targets: [
        DurablePairwiseTarget(
          recipientUserId: _peerUserId,
          recipientDeviceId: _peerDeviceId,
          exactCiphertext: Uint8List(1024),
        ),
      ],
    );
    final coordinator = PairwiseFanoutCoordinator(
      store: _ExistingOperationStore(operation),
      liveDevices: _UnusedLiveDevices(),
      claims: _UnusedClaims(),
      crypto: _UnusedCrypto(),
      clock: const _Clock(),
    );
    final gossipedUsers = <String>[];
    final adapter = PairwiseApplicationFanoutAdapter(
      coordinator,
      afterSuccessfulQueue: (peerUserId) async {
        gossipedUsers.add(peerUserId);
      },
    );

    final result = await adapter.prepareAndQueue(
      operationId: operation.operationId,
      eventId: eventIdHex,
      currentUserId: _currentUserId,
      currentDeviceId: _currentDeviceId,
      peerUserId: _peerUserId,
      openedPayload: payload,
      applicationEvent: ApplicationEventCommit(
        event: ApplicationEventRecord(
          version: 1,
          eventId: eventId,
          conversationId: Uint8List(32),
          kindValue: ApplicationEventKind.messageCreate.wireValue,
          senderUserId: protocolUuidBytes(_currentUserId),
          senderDeviceId: protocolUuidBytes(_currentDeviceId),
          senderCounter: 1,
          createdMs: 1,
          references: const [],
          body: MessageCreateBody(messageId: eventId, text: 'hello'),
        ),
        canonicalBytes: payload,
        currentUserId: _currentUserId,
        currentDeviceId: _currentDeviceId,
        conversationKind: 0,
        peerUserId: _peerUserId,
        localOrigin: true,
        authenticatedAt: DateTime.utc(2026),
      ),
    );

    expect(result, isA<Success<ApplicationFanoutOutcome>>());
    expect(gossipedUsers, [_peerUserId]);
  });
}

final class _ExistingOperationStore implements PairwiseTransportStore {
  const _ExistingOperationStore(this.operation);

  final DurablePairwiseOperation operation;

  @override
  Future<Result<DurablePairwiseOperation?>> readPreparedOperation(
    String operationId,
  ) async => Result.success(operation);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedLiveDevices implements PairwiseLiveDeviceResolverPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedClaims implements PairwiseSelectiveClaimPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedCrypto implements PairwiseOutboundPreparationPort {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Clock implements TimeSource {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026);
}
