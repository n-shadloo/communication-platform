import 'dart:typed_data';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/device_control_model.dart';

/// Primitive-only prepared transition crossing from pairwise crypto into sync.
/// All byte fields remain opaque to Dart and are committed by Drift under CAS.
final class PairwiseSyncSessionTransition {
  PairwiseSyncSessionTransition({
    required this.localDeviceId,
    required this.remoteUserId,
    required this.remoteDeviceId,
    required Uint8List sessionId,
    required Uint8List nextOpaqueState,
    required this.expectedStateVersion,
    required this.nextStateVersion,
    required this.nextSkippedKeyCount,
    required this.disposition,
    required this.repairState,
    Uint8List? repairAuthorization,
  }) : sessionId = Uint8List.fromList(sessionId),
       nextOpaqueState = Uint8List.fromList(nextOpaqueState),
       repairAuthorization = repairAuthorization == null
           ? null
           : Uint8List.fromList(repairAuthorization);

  final String localDeviceId;
  final String remoteUserId;
  final String remoteDeviceId;
  final Uint8List sessionId;
  final Uint8List nextOpaqueState;
  final int? expectedStateVersion;
  final int nextStateVersion;
  final int nextSkippedKeyCount;
  final int disposition;
  final int repairState;
  final Uint8List? repairAuthorization;
}

final class PairwiseSyncDeviceStateTransition {
  PairwiseSyncDeviceStateTransition({
    required Uint8List nextOpaqueState,
    required this.expectedStateVersion,
    required this.nextStateVersion,
  }) : nextOpaqueState = Uint8List.fromList(nextOpaqueState);

  final Uint8List nextOpaqueState;
  final int expectedStateVersion;
  final int nextStateVersion;
}

final class PairwiseSyncConsumedPrekey {
  const PairwiseSyncConsumedPrekey({
    required this.algorithm,
    required this.keyId,
  });

  /// 0 is classical X25519; 1 is post-quantum ML-KEM-768.
  final int algorithm;
  final int keyId;
}

final class PairwiseSyncReceiveCommit {
  PairwiseSyncReceiveCommit({
    required this.envelopeId,
    required this.opaqueEventId,
    required this.senderUserId,
    required this.senderDeviceId,
    required Uint8List replayMarker,
    required Uint8List openedOpaquePayload,
    required this.sessionTransition,
    this.demotedExistingSessionTransition,
    Uint8List? replacedSessionId,
    this.signedPrekeyId,
    this.pqSignedPrekeyId,
    this.deviceStateTransition,
    List<PairwiseSyncConsumedPrekey> consumedOneTimePrekeys = const [],
    this.applicationEvent,
    this.unsupportedApplicationEvent,
    this.deviceControlEvent,
    List<ApplicationEventCommit> historyApplicationEvents = const [],
  }) : replayMarker = Uint8List.fromList(replayMarker),
       openedOpaquePayload = Uint8List.fromList(openedOpaquePayload),
       replacedSessionId = replacedSessionId == null
           ? null
           : Uint8List.fromList(replacedSessionId),
       consumedOneTimePrekeys = List.unmodifiable(consumedOneTimePrekeys),
       historyApplicationEvents = List.unmodifiable(historyApplicationEvents);

  final String envelopeId;
  final String opaqueEventId;
  final String senderUserId;
  final String senderDeviceId;
  final Uint8List replayMarker;
  final Uint8List openedOpaquePayload;
  final PairwiseSyncSessionTransition sessionTransition;
  final PairwiseSyncSessionTransition? demotedExistingSessionTransition;
  final Uint8List? replacedSessionId;
  final int? signedPrekeyId;
  final int? pqSignedPrekeyId;
  final PairwiseSyncDeviceStateTransition? deviceStateTransition;
  final List<PairwiseSyncConsumedPrekey> consumedOneTimePrekeys;
  final ApplicationEventCommit? applicationEvent;
  final UnsupportedApplicationCommit? unsupportedApplicationEvent;
  final DeviceControlEvent? deviceControlEvent;
  final List<ApplicationEventCommit> historyApplicationEvents;
}
