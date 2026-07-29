import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';

abstract interface class PairwiseSessionCryptoPort implements Port {
  /// Parses only the public routing fields. The returned hint remains
  /// untrusted until the corresponding probe/decrypt operation authenticates it.
  Future<Result<PairwisePublicHeaderInspection>> inspectPublicHeader({
    required Uint8List envelope,
  });

  Future<Result<PairwiseInitiationResult>> initiate({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List senderDeviceId,
    required Uint8List recipientUserId,
    required Uint8List recipientDeviceId,
    required Uint8List recipientSelfSigningPublic,
    required ClaimedPrekeyBundle verifiedBundle,
    required Uint8List innerPayload,
    required int otherSessionsSkippedKeys,
    Uint8List? repairAuthorization,
  });

  Future<Result<PairwiseInitialSenderProjection>> probeInitial({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required Uint8List envelope,
  });

  Future<Result<AcceptedPairwiseInitial>> acceptVerifiedInitial({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required Uint8List envelope,
    required PairwiseInitialSenderProjection probe,
    required PeerPublicDevice authenticatedSenderDevice,
    required int otherSessionsSkippedKeys,
    PairwiseSessionState? existingPrimarySession,
    PairwiseSessionState? replacedSession,
  });

  Future<Result<PreparedPairwiseEnvelope>> encrypt({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required Uint8List innerPayload,
    required int otherSessionsSkippedKeys,
  });

  Future<Result<PairwiseRatchetDecryptResult>> decrypt({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required Uint8List envelope,
    required int otherSessionsSkippedKeys,
  });

  Future<Result<PreparedPairwiseEnvelope>> createAuthenticatedRepairRequest({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required int otherSessionsSkippedKeys,
  });

  Future<Result<AuthenticatedRepairAuthorization>>
  consumeAuthenticatedRepairRequest({
    required Uint8List deviceState,
    required int unixDay,
    required PairwiseSessionState session,
  });
}
