import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/pairwise/domain/pairwise_model.dart';

abstract interface class PairwiseTransportStore implements RepositoryPort {
  Future<Result<PairwisePreparationContext>> readPreparationContext({
    required String localDeviceId,
    required String remoteUserId,
    required String remoteDeviceId,
  });

  Future<Result<PairwiseInboundPreparationContext>> readInboundContext({
    required String localDeviceId,
    Uint8List? sessionId,
  });

  /// Returns exact durable bytes when [operationId] was already prepared.
  Future<Result<DurablePairwiseOperation?>> readPreparedOperation(
    String operationId,
  );

  /// Writes the sealed per-recipient rows, and retires the preparation that
  /// owed them.
  ///
  /// The two halves are one transaction because the second is what stops the
  /// first happening twice: a process that dies between them would come back to
  /// a preparation still owed against an outbox that already holds its bytes.
  Future<Result<void>> commitPreparedSend(PairwiseSendCommit commit);

  /// Commits a locally originated event, and records that its recipients are
  /// still owed.
  ///
  /// This is the whole of what a send does before the user sees it. Everything
  /// the old path did first — asking the server who the peer's devices are,
  /// claiming their prekeys, running the ratchet once per device — is described
  /// by the durable row this writes and is done against a message that already
  /// exists.
  Future<Result<void>> commitLocalEcho({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedLocalPayload,
    required ApplicationEventCommit applicationEvent,
  });

  /// Retires a preparation that resolved to no recipient at all.
  ///
  /// A conversation with nobody else in it is not a failure and never reaches
  /// the wire, so the row is removed and the message settles as local.
  Future<Result<void>> settleSendPreparation(String operationId);

  /// Returns whether anything was actually re-armed.
  ///
  /// A send the user asks to retry has exactly one durable failure behind it:
  /// either its preparation never produced ciphertext, or the ciphertext it
  /// produced was refused for good. Both are re-armed in place, against the
  /// message that is already on screen, which is the difference between
  /// retrying a message and writing a second one.
  Future<Result<bool>> rearmFailedSend(String operationId);

  /// Returns true only when the application event deduplication row was new.
  Future<Result<bool>> commitPreparedReceive(PairwiseReceiveCommit commit);

  Future<Result<void>> invalidateRemoteDevices({
    required String remoteUserId,
    required Set<String> remoteDeviceIds,
  });

  /// Invalidates sessions and pending targets absent from an authenticated live set.
  Future<Result<void>> reconcileRemoteLiveDevices({
    required String remoteUserId,
    required Set<String> liveDeviceIds,
  });

  /// Initial replay markers are pruned only for signed prekeys whose erasure was
  /// confirmed by the authenticated native device-state transition.
  /// Unapplied opaque payloads are never discarded.
  Future<Result<void>> pruneRetainedMetadata({
    required DateTime now,
    List<ErasedPairwiseSignedPrekeyPair> erasedSignedPrekeys = const [],
  });
}
