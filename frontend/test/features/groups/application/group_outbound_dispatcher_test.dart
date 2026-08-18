import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/group_outbound_dispatcher.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = '10000000-0000-4000-8000-000000000001';
const _aliceDevice = '20000000-0000-4000-8000-000000000001';
const _bob = '30000000-0000-4000-8000-000000000001';
const _carol = '40000000-0000-4000-8000-000000000001';

void main() {
  test(
    'routes exact work once per user and includes own devices only once',
    () async {
      final repository = _Repository(_work([_carol, _alice, _bob]));
      final envelopes = _Envelopes();
      final result = await GroupOutboundDispatcher(
        repository: repository,
        envelopes: envelopes,
      ).dispatchPending(currentUserId: _alice, currentDeviceId: _aliceDevice);

      expect(result, isA<Success<GroupOutboundDispatchReport>>());
      final report = (result as Success<GroupOutboundDispatchReport>).value;
      expect(report.workItems, 1);
      expect(report.fanoutOperations, 2);
      expect(envelopes.calls.map((call) => call.target), [_bob, _carol]);
      // Each recipient user gets its own pairwise operation, so each also
      // needs its own logical send identity: the durable outbox holds at most
      // one local application per event id.
      expect(envelopes.calls.map((call) => call.operationId), [
        'operation:$_bob',
        'operation:$_carol',
      ]);
      expect(envelopes.calls.map((call) => call.eventId), [
        'event:$_bob',
        'event:$_carol',
      ]);
      expect(envelopes.calls.map((call) => call.includeOwn), [true, false]);
      expect(envelopes.calls.every((call) => call.payload == '7,8,9'), isTrue);
      expect(repository.routed, ['operation']);
    },
  );

  test(
    'does not mark raw MLS work routed after a partial fanout failure',
    () async {
      final repository = _Repository(_work([_alice, _bob, _carol]));
      final result = await GroupOutboundDispatcher(
        repository: repository,
        envelopes: _Envelopes(failTarget: _carol),
      ).dispatchPending(currentUserId: _alice, currentDeviceId: _aliceDevice);

      expect(result, isA<FailureResult<GroupOutboundDispatchReport>>());
      expect(repository.routed, isEmpty);
    },
  );

  test('rejects persisted work that omits the current account', () async {
    final result = await GroupOutboundDispatcher(
      repository: _Repository(_work([_bob])),
      envelopes: _Envelopes(),
    ).dispatchPending(currentUserId: _alice, currentDeviceId: _aliceDevice);

    expect(result, isA<FailureResult<GroupOutboundDispatchReport>>());
    expect(
      (result as FailureResult<GroupOutboundDispatchReport>).failure,
      const SecurityFailure(SecurityFailureKind.integrityCheckFailed),
    );
  });
}

GroupOutboundWork _work(List<String> recipients) => GroupOutboundWork(
  operationId: 'operation',
  groupId: 'group',
  eventId: 'event',
  epoch: 1,
  openedMlsPayload: Uint8List.fromList([7, 8, 9]),
  recipientUserIds: recipients,
);

final class _EnvelopeCall {
  const _EnvelopeCall({
    required this.operationId,
    required this.eventId,
    required this.target,
    required this.includeOwn,
    required this.payload,
  });

  final String operationId;
  final String eventId;
  final String target;
  final bool includeOwn;
  final String payload;
}

final class _Envelopes implements GroupOutboundEnvelopePort {
  _Envelopes({this.failTarget});

  final String? failTarget;
  final calls = <_EnvelopeCall>[];

  @override
  Future<Result<void>> prepareAndQueue({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String targetUserId,
    required Uint8List openedMlsPayload,
    required bool includeOwnDevices,
  }) async {
    calls.add(
      _EnvelopeCall(
        operationId: operationId,
        eventId: eventId,
        target: targetUserId,
        includeOwn: includeOwnDevices,
        payload: openedMlsPayload.join(','),
      ),
    );
    return targetUserId == failTarget
        ? const Result.failure(TransportFailure(TransportFailureKind.timeout))
        : const Result.success(null);
  }
}

final class _Repository implements GroupRepositoryPort {
  _Repository(this.work);

  final GroupOutboundWork work;
  final routed = <String>[];

  @override
  Future<Result<List<GroupState>>> readGroupsPendingEviction({
    int limit = 20,
  }) async => const Result.success([]);

  @override
  Future<Result<List<GroupOutboundWork>>> readPendingOutbound({
    int limit = 20,
  }) async => Result.success([work]);

  @override
  Future<Result<void>> markOutboundRouted({required String operationId}) async {
    routed.add(operationId);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> commitMessage({
    required GroupState expectedGroup,
    required PreparedGroupMessage prepared,
    required bool developmentPreviewOnly,
  }) async => throw UnimplementedError();
  @override
  Future<Result<void>> commitTransition({
    required GroupState? expectedPrevious,
    required GroupState next,
    required PreparedGroupTransition prepared,
    required bool developmentPreviewOnly,
  }) async => throw UnimplementedError();
  @override
  Future<Result<void>> quarantine(GroupQuarantineRecord record) async =>
      throw UnimplementedError();
  @override
  Future<Result<GroupState?>> readGroup(String groupId) async =>
      throw UnimplementedError();
  @override
  Future<Result<Uint8List?>> readOpaqueMlsState(String groupId) async =>
      throw UnimplementedError();
  @override
  Stream<GroupState?> watchGroup(String groupId) => throw UnimplementedError();
  @override
  Stream<List<GroupMessage>> watchMessages(String groupId) =>
      throw UnimplementedError();
}
