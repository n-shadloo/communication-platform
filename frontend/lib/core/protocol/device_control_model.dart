import 'dart:typed_data';

import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';

abstract final class DeviceControlProtocolV1 {
  static const int version = 1;
  static const int maximumGossipHeads = 32;
  static const int maximumHistoryEventsPerBatch = 32;
  static const int maximumHistoryBatchBytes = 240 * 1024;
  static const int labelBucketBytes = 256;
  static const int maximumLabelScalars = 64;
  static const int maximumLabelBytes = 128;
}

enum HistorySourceCompleteness { full, partial }

enum HistoryUnavailableReason { noLocalHistory, sourcePartial, sourceLeaving }

final class DeviceLogHeadGossip {
  DeviceLogHeadGossip({
    required Uint8List userId,
    required this.sequence,
    required Uint8List hash,
  }) : userId = _copyExact(userId, 16),
       hash = _copyExact(hash, 32) {
    if (sequence < 0) {
      throw const DeviceControlFormatException();
    }
  }

  final Uint8List userId;
  final int sequence;
  final Uint8List hash;
}

sealed class DeviceControlEvent {
  DeviceControlEvent({
    required Uint8List eventId,
    required Uint8List senderUserId,
    required Uint8List senderDeviceId,
    Uint8List? targetDeviceId,
    Uint8List? transferId,
  }) : eventId = _copyExact(eventId, 16),
       senderUserId = _copyExact(senderUserId, 16),
       senderDeviceId = _copyExact(senderDeviceId, 16),
       targetDeviceId = targetDeviceId == null
           ? null
           : _copyExact(targetDeviceId, 16),
       transferId = transferId == null ? null : _copyExact(transferId, 16);

  final Uint8List eventId;
  final Uint8List senderUserId;
  final Uint8List senderDeviceId;
  final Uint8List? targetDeviceId;
  final Uint8List? transferId;
}

final class DeviceHeadGossipEvent extends DeviceControlEvent {
  DeviceHeadGossipEvent({
    required super.eventId,
    required super.senderUserId,
    required super.senderDeviceId,
    required List<DeviceLogHeadGossip> heads,
  }) : heads = List.unmodifiable(heads) {
    if (heads.isEmpty ||
        heads.length > DeviceControlProtocolV1.maximumGossipHeads) {
      throw const DeviceControlFormatException();
    }
  }

  final List<DeviceLogHeadGossip> heads;
}

final class HistoryTransferRequestEvent extends DeviceControlEvent {
  HistoryTransferRequestEvent({
    required super.eventId,
    required super.senderUserId,
    required super.senderDeviceId,
    required Uint8List targetDeviceId,
    required Uint8List transferId,
    required this.resumeAfterBatch,
  }) : super(targetDeviceId: targetDeviceId, transferId: transferId) {
    if (resumeAfterBatch < 0) {
      throw const DeviceControlFormatException();
    }
  }

  final int resumeAfterBatch;
}

final class HistoryTransferBatchEvent extends DeviceControlEvent {
  HistoryTransferBatchEvent({
    required super.eventId,
    required super.senderUserId,
    required super.senderDeviceId,
    required Uint8List targetDeviceId,
    required Uint8List transferId,
    required this.batchIndex,
    required this.finalBatch,
    required this.sourceCompleteness,
    required List<Uint8List> canonicalEvents,
  }) : canonicalEvents = List.unmodifiable(
         canonicalEvents.map(Uint8List.fromList),
       ),
       super(targetDeviceId: targetDeviceId, transferId: transferId) {
    final total = canonicalEvents.fold<int>(
      0,
      (sum, event) => sum + event.length,
    );
    if (batchIndex < 0 ||
        canonicalEvents.isEmpty ||
        canonicalEvents.length >
            DeviceControlProtocolV1.maximumHistoryEventsPerBatch ||
        total > DeviceControlProtocolV1.maximumHistoryBatchBytes) {
      throw const DeviceControlFormatException();
    }
  }

  final int batchIndex;
  final bool finalBatch;
  final HistorySourceCompleteness sourceCompleteness;
  final List<Uint8List> canonicalEvents;
}

final class HistoryTransferCompleteEvent extends DeviceControlEvent {
  HistoryTransferCompleteEvent({
    required super.eventId,
    required super.senderUserId,
    required super.senderDeviceId,
    required Uint8List targetDeviceId,
    required Uint8List transferId,
    required this.confirmedBatches,
  }) : super(targetDeviceId: targetDeviceId, transferId: transferId) {
    if (confirmedBatches < 0) {
      throw const DeviceControlFormatException();
    }
  }

  final int confirmedBatches;
}

final class HistoryTransferUnavailableEvent extends DeviceControlEvent {
  HistoryTransferUnavailableEvent({
    required super.eventId,
    required super.senderUserId,
    required super.senderDeviceId,
    required Uint8List targetDeviceId,
    required Uint8List transferId,
    required this.reason,
  }) : super(targetDeviceId: targetDeviceId, transferId: transferId);

  final HistoryUnavailableReason reason;
}

final class DeviceLabelCiphertext {
  DeviceLabelCiphertext(Uint8List bytes)
    : bytes = _copyExact(bytes, DeviceControlProtocolV1.labelBucketBytes);

  final Uint8List bytes;
}

final class DeviceControlFormatException implements Exception {
  const DeviceControlFormatException();
}

Uint8List copyDeviceIdentityBytes(IdentityKeyPackage package) =>
    Uint8List.fromList(package.opaqueBytes);

Uint8List _copyExact(Uint8List value, int length) {
  if (value.length != length) {
    throw const DeviceControlFormatException();
  }
  return Uint8List.fromList(value);
}
