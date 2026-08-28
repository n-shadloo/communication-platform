import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/owed_device_log_gossip.dart';
import 'package:communication_platform/features/messaging/infrastructure/pairwise_send_preparation_adapter.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_transport_store.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentUserId = '10000000-0000-4000-8000-000000000001';
const _currentDeviceId = '10000000-0000-4000-8000-000000000002';
const _peerUserId = '10000000-0000-4000-8000-000000000003';
const _peerDeviceId = '10000000-0000-4000-8000-000000000004';

void main() {
  final eventId = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
  final eventIdHex = protocolBytesToHex(eventId);
  final payload = Uint8List.fromList([1, 2, 3]);

  PendingSendPreparation owed() => PendingSendPreparation(
    operationId: 'application:$eventIdHex',
    eventId: eventIdHex,
    localUserId: _currentUserId,
    localDeviceId: _currentDeviceId,
    peerUserId: _peerUserId,
    attempt: 1,
  );

  PairwiseSendPreparationAdapter adapterOver(
    PairwiseTransportStore store,
    OwedDeviceLogGossip owed,
  ) => PairwiseSendPreparationAdapter(
    PairwiseFanoutCoordinator(
      store: store,
      liveDevices: _UnusedLiveDevices(),
      claims: _UnusedClaims(),
      crypto: _UnusedCrypto(),
      clock: const _Clock(),
    ),
    onPreparedForPeer: owed.owe,
  );

  OwedDeviceLogGossip ledgerOver(
    List<String> gossiped, {
    bool gossipThrows = false,
  }) => OwedDeviceLogGossip(
    advertise: (peerUserId) async {
      gossiped.add(peerUserId);
      if (gossipThrows) {
        throw StateError('gossip');
      }
      return const Result.success(null);
    },
    clock: const _Clock(),
  );

  test('an already queued send settles and still owes gossip', () async {
    final store = _ExistingOperationStore(
      DurablePairwiseOperation(
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
      ),
    );
    final gossiped = <String>[];
    final ledger = ledgerOver(gossiped);

    final result = await adapterOver(store, ledger).prepare(owed());

    // The debt is recorded and nothing more. Awaiting the round here is what
    // used to put a second fan-out between a sealed envelope and its POST.
    expect(result, isA<Success<void>>());
    expect(store.settled, ['application:$eventIdHex']);
    expect(gossiped, isEmpty);
    expect(ledger.owed, {_peerUserId});

    await ledger.settle();

    expect(gossiped, [_peerUserId]);
    expect(ledger.owed, isEmpty);
  });

  test('the envelope is postable before gossip runs', () async {
    final store = _ExistingOperationStore(
      DurablePairwiseOperation(
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
      ),
    );
    final order = <String>[];
    final ledger = OwedDeviceLogGossip(
      advertise: (peerUserId) async {
        await Future<void>.delayed(Duration.zero);
        order.add('gossip');
        return const Result.success(null);
      },
      clock: const _Clock(),
    );

    await adapterOver(store, ledger).prepare(owed());
    order.add('prepared');
    await ledger.settle();

    expect(order, ['prepared', 'gossip']);
  });

  test('gossip failing is never the send failing', () async {
    final store = _ExistingOperationStore(
      DurablePairwiseOperation(
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
      ),
    );

    final ledger = ledgerOver(<String>[], gossipThrows: true);

    final result = await adapterOver(store, ledger).prepare(owed());
    await ledger.settle();

    // Structurally, not by a swallowed catch on the send path: `prepare` has
    // already returned by the time anything gossips, and there is no value for
    // it to have observed.
    expect(result, isA<Success<void>>());
    expect(ledger.owed, isEmpty);
  });

  test('a preparation that fails owes nothing', () async {
    final gossiped = <String>[];
    final ledger = ledgerOver(gossiped);

    final result = await adapterOver(
      _UnreadableStore(),
      ledger,
    ).prepare(owed());
    await ledger.settle();

    expect(result, isA<FailureResult<void>>());
    expect(gossiped, isEmpty);
  });
}

final class _ExistingOperationStore implements PairwiseTransportStore {
  _ExistingOperationStore(this.operation);

  final DurablePairwiseOperation operation;
  final List<String> settled = [];

  @override
  Future<Result<DurablePairwiseOperation?>> readPreparedOperation(
    String operationId,
  ) async => Result.success(operation);

  @override
  Future<Result<void>> settleSendPreparation(String operationId) async {
    settled.add(operationId);
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnreadableStore implements PairwiseTransportStore {
  @override
  Future<Result<DurablePairwiseOperation?>> readPreparedOperation(
    String operationId,
  ) async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));

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
