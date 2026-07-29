import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
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

  Future<Result<void>> commitPreparedSend(PairwiseSendCommit commit);

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
