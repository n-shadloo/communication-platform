import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/messaging/infrastructure/pairwise_application_fanout_adapter.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_transport_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentUserId = '10000000-0000-4000-8000-000000000001';
const _currentDeviceId = '10000000-0000-4000-8000-000000000002';
const _peerUserId = '10000000-0000-4000-8000-000000000003';

void main() {
  test('an echo commits without resolving a device', () async {
    final eventId = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
    final eventIdHex = protocolBytesToHex(eventId);
    final payload = Uint8List.fromList([1, 2, 3]);
    final store = _RecordingStore();
    final adapter = PairwiseApplicationFanoutAdapter(
      PairwiseFanoutCoordinator(
        store: store,
        liveDevices: _UnusedLiveDevices(),
        claims: _UnusedClaims(),
        crypto: _UnusedCrypto(),
        clock: const _Clock(),
      ),
    );

    final result = await adapter.commitLocalEcho(
      operationId: 'application:$eventIdHex',
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

    expect(result, isA<Success<void>>());
    expect(store.echoes, ['application:$eventIdHex']);
    expect(store.peers, [_peerUserId]);
  });

  test('a retry asks for the operation the message already has', () async {
    final store = _RecordingStore();
    final adapter = PairwiseApplicationFanoutAdapter(
      PairwiseFanoutCoordinator(
        store: store,
        liveDevices: _UnusedLiveDevices(),
        claims: _UnusedClaims(),
        crypto: _UnusedCrypto(),
        clock: const _Clock(),
      ),
    );

    final result = await adapter.retryFailedSend('application:abcd');

    expect((result as Success<bool>).value, isTrue);
    expect(store.rearmed, ['application:abcd']);
  });
}

final class _RecordingStore implements PairwiseTransportStore {
  final List<String> echoes = [];
  final List<String> peers = [];
  final List<String> rearmed = [];

  @override
  Future<Result<void>> commitLocalEcho({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedLocalPayload,
    required ApplicationEventCommit applicationEvent,
  }) async {
    echoes.add(operationId);
    peers.add(peerUserId);
    return const Result.success(null);
  }

  @override
  Future<Result<bool>> rearmFailedSend(String operationId) async {
    rearmed.add(operationId);
    return const Result.success(true);
  }

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
