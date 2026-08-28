import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/application/ports/device_control_crypto_port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/device_control_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/owed_device_log_gossip.dart';
import 'package:communication_platform/features/devices/application/ports/linked_device_ports.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:drift/drift.dart';

/// Sends authenticated device-log heads inside ordinary hybrid pairwise
/// envelopes. The REST device/log endpoints are never used as gossip channels.
final class DeviceLogGossipCoordinator {
  const DeviceLogGossipCoordinator({
    required this.database,
    required this.local,
    required this.protocol,
    required this.controlCrypto,
    required this.fanout,
    required this.currentUserId,
    required this.currentDeviceId,
  });

  final LocalDatabase database;
  final LinkedDeviceLocalPort local;
  final ApplicationProtocolPort protocol;
  final DeviceControlCryptoPort controlCrypto;
  final PairwiseFanoutCoordinator fanout;
  final String currentUserId;
  final String currentDeviceId;

  Future<Result<void>> queueForUser(String peerUserId) async {
    final posture = await local.readGlobalSecurityState();
    if (posture case Success(
      value: final state,
    ) when state != GlobalSecurityState.normal) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final rows = await database
        .customSelect(
          '''
SELECT l.user_id, l.sequence, l.record_hash
FROM device_log l
JOIN (
  SELECT user_id, MAX(sequence) AS sequence
  FROM device_log
  GROUP BY user_id
) h ON h.user_id = l.user_id AND h.sequence = l.sequence
ORDER BY l.user_id
LIMIT 32
''',
          readsFrom: {database.deviceLogRecords},
        )
        .get();
    if (rows.isEmpty) {
      return const Result.success(null);
    }
    final idResult = await protocol.generateEventId();
    if (idResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final event = DeviceHeadGossipEvent(
      eventId: (idResult as Success<Uint8List>).value,
      senderUserId: protocolUuidBytes(currentUserId),
      senderDeviceId: protocolUuidBytes(currentDeviceId),
      heads: [
        for (final row in rows)
          DeviceLogHeadGossip(
            userId: protocolUuidBytes(row.read<String>('user_id')),
            sequence: row.read<int>('sequence'),
            hash: row.read<Uint8List>('record_hash'),
          ),
      ],
    );
    final encoded = await controlCrypto.encodeDeviceControl(event);
    if (encoded case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final eventId = protocolBytesToHex(event.eventId);
    final queued = await fanout.prepareAndQueue(
      operationId: 'device-head-gossip:$eventId',
      eventId: eventId,
      currentUserId: currentUserId,
      currentDeviceId: currentDeviceId,
      peerUserId: peerUserId,
      openedOpaquePayload: (encoded as Success<Uint8List>).value,
    );
    return queued.fold(
      onSuccess: (_) => const Result.success(null),
      onFailure: Result.failure,
    );
  }
}

/// Pays the device-log advertisements this cycle's sends owed.
///
/// It runs where the delivery cycle already runs work it owes rather than work
/// somebody is waiting for, and that position is load-bearing twice over.
///
/// It is **after the first outbox pass**, which is the rule ADR-060 states: a
/// cycle sends the user's message before it does anything on anybody else's
/// behalf. Gossip used to sit in front of that, awaited by the preparation that
/// discovered the debt.
///
/// It is also **after the inbox has committed**, which makes the advertisement
/// better rather than merely later. The inbound half of a cycle is exactly what
/// can advance a device-log head, so gossip run here advertises the heads this
/// cycle just learned instead of the ones it started with. The rows it queues
/// are sealed by the second preparation pass and leave on the second outbox
/// pass, in the same cycle.
final class DeviceLogGossipPostInboxWork implements PostInboxCommitWorkPort {
  const DeviceLogGossipPostInboxWork(this.owed);

  final OwedDeviceLogGossip owed;

  @override
  Future<void> run() => owed.settle();
}
