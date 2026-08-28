import 'dart:convert';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/application/ports/device_control_crypto_port.dart';
import 'package:communication_platform/core/protocol/device_control_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/linked_device_ports.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/history_transfer_model.dart';
import 'package:drift/drift.dart';

/// Resumable history transfer over ordinary pairwise envelopes.
///
/// This coordinator deliberately has no vault/history REST dependency. The
/// source reads only its local canonical application-event table and the
/// receiver commits each bounded batch transactionally with a unique control
/// event and event-id deduplication.
final class HistoryTransferCoordinator {
  const HistoryTransferCoordinator({
    required this.database,
    required this.applicationProtocol,
    required this.controlCrypto,
    required this.fanout,
    required this.local,
    required this.currentUserId,
    required this.currentDeviceId,
  });

  final LocalDatabase database;
  final ApplicationProtocolPort applicationProtocol;
  final DeviceControlCryptoPort controlCrypto;
  final PairwiseFanoutCoordinator fanout;
  final LinkedDeviceLocalPort local;
  final String currentUserId;
  final String currentDeviceId;

  Future<Result<String>> requestHistory({
    required String sourceDeviceId,
  }) async {
    if (!_uuid(sourceDeviceId) ||
        sourceDeviceId.toLowerCase() == currentDeviceId.toLowerCase()) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final posture = await local.readGlobalSecurityState();
    if (posture case Success(
      value: final state,
    ) when state != GlobalSecurityState.normal) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final eventId = await applicationProtocol.generateEventId();
    if (eventId case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final transferBytes = (eventId as Success<Uint8List>).value;
    final generated = await applicationProtocol.generateEventId();
    if (generated case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final id = (generated as Success<Uint8List>).value;
    final request = HistoryTransferRequestEvent(
      eventId: transferBytes,
      senderUserId: protocolUuidBytes(currentUserId),
      senderDeviceId: protocolUuidBytes(currentDeviceId),
      targetDeviceId: protocolUuidBytes(sourceDeviceId),
      transferId: id,
      resumeAfterBatch: 0,
    );
    final encoded = await controlCrypto.encodeDeviceControl(request);
    if (encoded case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    await database
        .into(database.historyTransfers)
        .insertOnConflictUpdate(
          HistoryTransfersCompanion.insert(
            transferId: _hex(id),
            manifestCiphertext: Uint8List.fromList(
              utf8.encode('opaque-transfer-v1'),
            ),
            sourceDeviceId: Value(sourceDeviceId.toLowerCase()),
            targetDeviceId: Value(currentDeviceId.toLowerCase()),
            direction: const Value(0),
            state: Value(HistoryTransferState.waitingForSource.index),
            sourceCompleteness: 1,
          ),
        );
    final queued = await fanout.prepareAndQueue(
      operationId: 'history-request:${_hex(id)}',
      eventId: _hex(request.eventId),
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: currentUserId,
      openedOpaquePayload: (encoded as Success<Uint8List>).value,
      onlyRecipientDeviceId: sourceDeviceId,
    );
    if (queued case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return Result.success(_hex(id));
  }

  Future<Result<bool>> sendNextBatch({
    required String transferId,
    required String targetDeviceId,
    required int batchIndex,
    HistorySourceCompleteness completeness = HistorySourceCompleteness.full,
  }) async {
    final posture = await local.readGlobalSecurityState();
    if (posture case Success(
      value: final state,
    ) when state != GlobalSecurityState.normal) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final row = await (database.select(
      database.historyTransfers,
    )..where((t) => t.transferId.equals(transferId))).getSingleOrNull();
    if (row == null ||
        row.direction != 1 ||
        row.sourceDeviceId != currentDeviceId.toLowerCase() ||
        row.targetDeviceId != targetDeviceId.toLowerCase() ||
        row.nextBatchIndex != batchIndex) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final pending = await _pendingSourceControl(row.manifestCiphertext);
    if (pending != null) {
      return _queuePendingSourceControl(
        transferId: transferId,
        targetDeviceId: targetDeviceId,
        row: row,
        control: pending.$1,
        exactControl: pending.$2,
      );
    }
    final candidates =
        await (database.select(database.storedApplicationEvents)
              ..orderBy([
                (e) => OrderingTerm.asc(e.createdMs),
                (e) => OrderingTerm.asc(e.eventId),
              ])
              ..limit(
                DeviceControlProtocolV1.maximumHistoryEventsPerBatch + 1,
                offset: row.eventProgress,
              ))
            .get();
    if (candidates.isEmpty) {
      final unavailable = HistoryTransferUnavailableEvent(
        eventId: await _eventId(),
        senderUserId: protocolUuidBytes(currentUserId),
        senderDeviceId: protocolUuidBytes(currentDeviceId),
        targetDeviceId: protocolUuidBytes(targetDeviceId),
        transferId: protocolUuidBytesFromHex(transferId),
        reason: HistoryUnavailableReason.noLocalHistory,
      );
      final encoded = await controlCrypto.encodeDeviceControl(unavailable);
      if (encoded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final exact = (encoded as Success<Uint8List>).value;
      final saved = await _savePendingControl(row: row, exactControl: exact);
      if (saved case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      return _queuePendingSourceControl(
        transferId: transferId,
        targetDeviceId: targetDeviceId,
        row: row,
        control: unavailable,
        exactControl: exact,
      );
    }
    final canonical = <Uint8List>[];
    var total = 0;
    for (final event in candidates.take(
      DeviceControlProtocolV1.maximumHistoryEventsPerBatch,
    )) {
      final bytes = Uint8List.fromList(event.canonicalEvent);
      if (total + bytes.length >
          DeviceControlProtocolV1.maximumHistoryBatchBytes) {
        break;
      }
      canonical.add(bytes);
      total += bytes.length;
    }
    if (canonical.isEmpty) {
      final unavailable = HistoryTransferUnavailableEvent(
        eventId: await _eventId(),
        senderUserId: protocolUuidBytes(currentUserId),
        senderDeviceId: protocolUuidBytes(currentDeviceId),
        targetDeviceId: protocolUuidBytes(targetDeviceId),
        transferId: protocolUuidBytesFromHex(transferId),
        reason: HistoryUnavailableReason.sourcePartial,
      );
      final encoded = await controlCrypto.encodeDeviceControl(unavailable);
      if (encoded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final exact = (encoded as Success<Uint8List>).value;
      final saved = await _savePendingControl(row: row, exactControl: exact);
      if (saved case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      return _queuePendingSourceControl(
        transferId: transferId,
        targetDeviceId: targetDeviceId,
        row: row,
        control: unavailable,
        exactControl: exact,
      );
    }
    final batch = HistoryTransferBatchEvent(
      eventId: await _eventId(),
      senderUserId: protocolUuidBytes(currentUserId),
      senderDeviceId: protocolUuidBytes(currentDeviceId),
      targetDeviceId: protocolUuidBytes(targetDeviceId),
      transferId: protocolUuidBytesFromHex(transferId),
      batchIndex: batchIndex,
      finalBatch: candidates.length == canonical.length,
      sourceCompleteness: completeness,
      canonicalEvents: canonical,
    );
    final encoded = await controlCrypto.encodeDeviceControl(batch);
    if (encoded case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final exact = (encoded as Success<Uint8List>).value;
    final saved = await _savePendingControl(row: row, exactControl: exact);
    if (saved case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return _queuePendingSourceControl(
      transferId: transferId,
      targetDeviceId: targetDeviceId,
      row: row,
      control: batch,
      exactControl: exact,
    );
  }

  Future<Result<void>> markNoSource(String transferId) =>
      _updateState(transferId, HistoryTransferState.noSource);
  Future<Result<void>> markGroupReinviteRequired(String transferId) =>
      _updateState(transferId, HistoryTransferState.groupReinviteRequired);
  Future<Result<void>> markQueueGapRecovery(String transferId) =>
      _updateState(transferId, HistoryTransferState.queueGapRecovery);

  Future<Result<void>> _send(
    Uint8List encoded,
    String target,
    String op,
  ) async =>
      (await fanout.prepareAndQueue(
        operationId: op,
        eventId: op,
        currentUserId: currentUserId,
        currentDeviceId: currentDeviceId,
        peerUserId: currentUserId,
        openedOpaquePayload: encoded,
        onlyRecipientDeviceId: target,
      )).fold(
        onSuccess: (_) => const Result.success(null),
        onFailure: Result.failure,
      );

  Future<Result<void>> _updateState(
    String transferId,
    HistoryTransferState state,
  ) async {
    try {
      await (database.update(
        database.historyTransfers,
      )..where((t) => t.transferId.equals(transferId))).write(
        HistoryTransfersCompanion(
          state: Value(state.index),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<(DeviceControlEvent, Uint8List)?> _pendingSourceControl(
    Uint8List bytes,
  ) async {
    const magic = <int>[67, 80, 68, 67, 86, 48, 48, 49];
    if (bytes.length < magic.length ||
        !Iterable<int>.generate(
          magic.length,
        ).every((index) => bytes[index] == magic[index])) {
      return null;
    }
    final decoded = await controlCrypto.decodeDeviceControl(bytes);
    if (decoded case Success(value: final control)) {
      return (control, Uint8List.fromList(bytes));
    }
    throw const _CorruptTransfer();
  }

  Future<Result<void>> _savePendingControl({
    required HistoryTransfer row,
    required Uint8List exactControl,
  }) async {
    try {
      final changed =
          await (database.update(database.historyTransfers)..where(
                (transfer) =>
                    transfer.transferId.equals(row.transferId) &
                    transfer.nextBatchIndex.equals(row.nextBatchIndex) &
                    transfer.direction.equals(1),
              ))
              .write(
                HistoryTransfersCompanion(
                  manifestCiphertext: Value(exactControl),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      return changed == 1
          ? const Result.success(null)
          : const Result.failure(
              ValidationFailure(ValidationFailureKind.conflict),
            );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<Result<bool>> _queuePendingSourceControl({
    required String transferId,
    required String targetDeviceId,
    required HistoryTransfer row,
    required DeviceControlEvent control,
    required Uint8List exactControl,
  }) async {
    if (control.transferId == null ||
        _hex(control.transferId!) != transferId ||
        control.targetDeviceId == null ||
        _hex(control.targetDeviceId!) !=
            targetDeviceId.replaceAll('-', '').toLowerCase()) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    final op = switch (control) {
      HistoryTransferBatchEvent(:final batchIndex) =>
        'history-batch:$transferId:$batchIndex',
      HistoryTransferUnavailableEvent() => 'history-unavailable:$transferId',
      _ => '',
    };
    if (op.isEmpty) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    final queued = await _send(exactControl, targetDeviceId, op);
    if (queued case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final (nextBatch, nextProgress, nextState, isFinal) = switch (control) {
        HistoryTransferBatchEvent(
          :final batchIndex,
          :final canonicalEvents,
          :final finalBatch,
          :final sourceCompleteness,
        ) =>
          (
            batchIndex + 1,
            row.eventProgress + canonicalEvents.length,
            finalBatch
                ? HistoryTransferState.done
                : sourceCompleteness == HistorySourceCompleteness.partial
                ? HistoryTransferState.partialTransfer
                : HistoryTransferState.transferring,
            finalBatch,
          ),
        HistoryTransferUnavailableEvent(:final reason) => (
          row.nextBatchIndex,
          row.eventProgress,
          reason == HistoryUnavailableReason.sourcePartial
              ? HistoryTransferState.done
              : HistoryTransferState.noSource,
          true,
        ),
        _ => throw const _CorruptTransfer(),
      };
      await (database.update(
        database.historyTransfers,
      )..where((transfer) => transfer.transferId.equals(transferId))).write(
        HistoryTransfersCompanion(
          manifestCiphertext: Value(
            Uint8List.fromList(utf8.encode('opaque-transfer-v1')),
          ),
          nextBatchIndex: Value(nextBatch),
          eventProgress: Value(nextProgress),
          state: Value(nextState.index),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      return Result.success(isFinal);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<Uint8List> _eventId() async {
    final result = await applicationProtocol.generateEventId();
    if (result case Success(value: final value)) return value;
    throw const _CorruptTransfer();
  }

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  bool _uuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
  Uint8List protocolUuidBytes(String value) => Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(value.replaceAll('-', '').substring(i, i + 2), radix: 16),
  ]);
  Uint8List protocolUuidBytesFromHex(String value) => Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}

final class _CorruptTransfer implements Exception {
  const _CorruptTransfer();
}

/// Bounded post-inbox sender. A newly authenticated request is persisted by the
/// ordinary pairwise receive transaction before this work is allowed to run.
final class HistoryTransferPostInboxWork implements PostInboxCommitWorkPort {
  const HistoryTransferPostInboxWork(
    this.coordinator, {
    this.maximumBatchesPerRun = 4,
  });

  final HistoryTransferCoordinator coordinator;
  final int maximumBatchesPerRun;

  @override
  Future<void> run() async {
    final rows =
        await (coordinator.database.select(
                coordinator.database.historyTransfers,
              )
              ..where(
                (row) =>
                    row.direction.equals(1) &
                    row.state.isIn([
                      HistoryTransferState.waitingForSource.index,
                      HistoryTransferState.transferring.index,
                      HistoryTransferState.partialTransfer.index,
                    ]),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)])
              ..limit(maximumBatchesPerRun))
            .get();
    for (final row in rows) {
      final checkpoint = await coordinator.database
          .select(coordinator.database.syncCheckpoints)
          .getSingleOrNull();
      final completeness =
          row.sourceCompleteness == 1 || (checkpoint?.queueGapState ?? 0) != 0
          ? HistorySourceCompleteness.partial
          : HistorySourceCompleteness.full;
      await coordinator.sendNextBatch(
        transferId: row.transferId,
        targetDeviceId: row.targetDeviceId,
        batchIndex: row.nextBatchIndex,
        completeness: completeness,
      );
    }
  }
}
