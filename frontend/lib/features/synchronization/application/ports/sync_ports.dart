import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

abstract interface class SyncRemotePort implements Port {
  Future<Result<DrainPage>> drain({required int limit});

  Future<Result<int>> acknowledge(List<String> envelopeIds);

  Future<Result<OutboxAcceptance>> send(OutboxBatch batch);
}

abstract interface class DurableSyncStore implements Port {
  Stream<SyncProjection> watchProjection();

  Future<Result<SyncProjection>> readProjection();

  Future<Result<void>> queuePreparedOperation({
    required String operationId,
    required String eventId,
    required List<PreparedOutboxTarget> targets,
  });

  Future<Result<void>> requestAuthoritativeDrain();

  Future<Result<void>> persistDrainPage(DrainPage page);

  Future<Result<SyncEnvelope?>> beginNextEnvelopeInspection({
    required DateTime now,
  });

  Future<Result<bool>> commitOpaqueInspection({
    required String envelopeId,
    required OpaqueEnvelopeInspection inspection,
  });

  Future<Result<void>> blockEnvelopeForQueueGap(String envelopeId);

  Future<Result<void>> recordEnvelopeInspectionRetry({
    required String envelopeId,
    required DateTime retryAt,
  });

  Future<Result<void>> recordEnvelopeRejection({
    required String envelopeId,
    required int reasonCode,
  });

  Future<Result<AcknowledgementBatch?>> beginAcknowledgementBatch({
    required DateTime now,
    required int maximumIds,
  });

  Future<Result<void>> recordAcknowledgementSuccess({
    required AcknowledgementBatch batch,
    required DateTime now,
  });

  Future<Result<void>> recordAcknowledgementFailure({
    required AcknowledgementBatch batch,
    required DateTime retryAt,
  });

  Future<Result<OutboxBatch?>> beginNextOutboxBatch({required DateTime now});

  Future<Result<void>> recordOutboxAcceptance({
    required OutboxBatch batch,
    required OutboxAcceptance acceptance,
    required DateTime now,
  });

  Future<Result<void>> recordOutboxRetry({
    required OutboxBatch batch,
    required DateTime retryAt,
  });

  Future<Result<void>> recordOutboxPermanentFailure({
    required OutboxBatch batch,
    required DateTime now,
  });

  Future<Result<List<StaleDeviceRefreshWork>>> pendingStaleDeviceRefreshes({
    required DateTime now,
  });

  Future<Result<void>> completeStaleDeviceRefresh(String userId);

  Future<Result<void>> retryStaleDeviceRefresh({
    required String userId,
    required DateTime retryAt,
  });

  Future<Result<void>> markConnectionPhase(SyncConnectionPhase phase);

  Future<Result<DurableReconnectState>> scheduleReconnect({
    required DateTime dueAt,
  });

  Future<Result<DurableReconnectState>> readReconnectState();

  Future<Result<void>> clearReconnect({required DateTime? syncedAt});

  Future<Result<void>> recordSuccessfulSync(DateTime syncedAt);

  Future<Result<void>> markGroupRecovered(String groupId);

  Future<Result<void>> markGroupLeft(String groupId);
}

/// Inspects opaque fixture bytes without mutating crypto or application state.
///
/// A later protocol piece will replace this with a bounded crypto-core preparation
/// step. When [allowPotentiallyMls] is false, an implementation must never advance
/// MLS state.
abstract interface class OpaqueEnvelopeInspector implements Port {
  Future<Result<OpaqueEnvelopeInspection>> inspect({
    required String envelopeId,
    required Uint8List exactCiphertext,
    required bool allowPotentiallyMls,
  });
}

abstract interface class StaleDeviceRefreshPort implements Port {
  Future<Result<void>> refreshUserDevices(String userId);
}

/// Best-effort application work triggered only after inbox commits complete.
abstract interface class PostInboxCommitWorkPort implements Port {
  Future<void> run();
}

abstract interface class JitterSource implements Port {
  int nextInt(int upperBoundExclusive);
}

abstract interface class NetworkAvailabilityPort implements Port {
  NetworkAvailability get current;

  Stream<NetworkAvailability> get changes;
}

abstract interface class ApplicationLifecyclePort implements Port {
  ApplicationExecutionState get current;

  Stream<ApplicationExecutionState> get changes;
}

abstract interface class BestEffortPollingPort implements Port {
  Stream<void> get triggers;

  Future<void> schedule({required Duration minimumInterval});

  Future<void> cancel();
}

abstract interface class RealtimeSyncPort implements Port {
  Stream<void> get durableEnvelopeHints;

  Stream<RealtimeDisconnect> get disconnects;

  Future<Result<void>> connect();

  void markStableConnection();

  Future<void> close();
}

abstract interface class DelayPort implements Port {
  Future<void> wait(Duration delay);
}

/// The platform edges one delivery session binds to, resolved together.
///
/// They are grouped because they share a lifetime and a failure mode: each one
/// holds an operating-system resource — an observer, a timer — that must be
/// released when the session stops, and a session that resolved some of them
/// has leaked the rest. Composing them behind one port is also what lets a test
/// drive the real supervisor without a device: connectivity and the widget
/// binding are platform channels, real timers cannot be waited out, and the
/// deferred scheduler does not exist yet.
abstract interface class DeliveryPlatformPorts implements Port {
  NetworkAvailabilityPort get network;

  ApplicationLifecyclePort get lifecycle;

  BestEffortPollingPort get polling;

  /// Wall-clock waiting, for reconnect backoff and the stable-connection
  /// threshold. It belongs with the others because it is the same kind of
  /// thing: a real timer the operating system owns, which a test must be able
  /// to replace rather than wait out.
  DelayPort get delay;

  Future<void> dispose();
}
