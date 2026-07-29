// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

final class SyncEngineLimits {
  const SyncEngineLimits({
    this.drainPageSize = 100,
    this.maximumDrainPagesPerRun = 100,
    this.maximumInspectionsPerRun = 1000,
    this.maximumAcknowledgementBatchesPerRun = 100,
    this.maximumOutboxBatchesPerRun = 100,
    this.maximumStaleRefreshesPerRun = 32,
  }) : assert(drainPageSize >= 1 && drainPageSize <= 100),
       assert(maximumDrainPagesPerRun > 0),
       assert(maximumInspectionsPerRun > 0),
       assert(maximumAcknowledgementBatchesPerRun > 0),
       assert(maximumOutboxBatchesPerRun > 0),
       assert(maximumStaleRefreshesPerRun > 0);

  final int drainPageSize;
  final int maximumDrainPagesPerRun;
  final int maximumInspectionsPerRun;
  final int maximumAcknowledgementBatchesPerRun;
  final int maximumOutboxBatchesPerRun;
  final int maximumStaleRefreshesPerRun;
}

final class SyncRetryPolicy {
  const SyncRetryPolicy({
    this.baseDelay = const Duration(seconds: 1),
    this.maximumDelay = const Duration(minutes: 15),
  });

  final Duration baseDelay;
  final Duration maximumDelay;

  Duration delayFor({
    required int attempt,
    required Failure failure,
    required JitterSource jitter,
  }) {
    if (failure case BackendFailure(
      code: BackendFailureCode.rateLimited,
      retryAfter: final retryAfter?,
    )) {
      return retryAfter;
    }
    final exponent = (attempt - 1).clamp(0, 20);
    final multiplier = 1 << exponent;
    final uncapped = baseDelay.inMilliseconds * multiplier;
    final capMilliseconds = uncapped > maximumDelay.inMilliseconds
        ? maximumDelay.inMilliseconds
        : uncapped;
    if (capMilliseconds <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: jitter.nextInt(capMilliseconds + 1));
  }
}

/// Crash-safe coordinator for the durable queue only.
///
/// All network requests are preceded by a Drift journal transition. A response is
/// recorded in a second transaction. Consequently process death can only cause an
/// idempotent acknowledgement or exact-ciphertext send to be retried.
final class DurableSyncEngine {
  DurableSyncEngine({
    required DurableSyncStore store,
    required SyncRemotePort remote,
    required OpaqueEnvelopeInspector inspector,
    required StaleDeviceRefreshPort staleDeviceRefresh,
    required TimeSource clock,
    required JitterSource jitter,
    this.retryPolicy = const SyncRetryPolicy(),
    this.limits = const SyncEngineLimits(),
  }) : _store = store,
       _remote = remote,
       _inspector = inspector,
       _staleDeviceRefresh = staleDeviceRefresh,
       _clock = clock,
       _jitter = jitter;

  final DurableSyncStore _store;
  final SyncRemotePort _remote;
  final OpaqueEnvelopeInspector _inspector;
  final StaleDeviceRefreshPort _staleDeviceRefresh;
  final TimeSource _clock;
  final JitterSource _jitter;
  final SyncRetryPolicy retryPolicy;
  final SyncEngineLimits limits;

  Future<Result<SyncRunReport>>? _activeRun;

  Future<Result<void>> queuePreparedOperation({
    required String operationId,
    required String eventId,
    required List<PreparedOutboxTarget> targets,
  }) => _store.queuePreparedOperation(
    operationId: operationId,
    eventId: eventId,
    targets: targets,
  );

  Future<Result<SyncRunReport>> synchronize() {
    final active = _activeRun;
    if (active != null) {
      return active;
    }
    final run = _run();
    _activeRun = run;
    return run.whenComplete(() {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    });
  }

  Future<Result<SyncRunReport>> _run() async {
    final phaseResult = await _store.markConnectionPhase(
      SyncConnectionPhase.draining,
    );
    if (phaseResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }

    var inspected = 0;
    var acknowledged = 0;
    var sent = 0;
    var drainedPages = 0;
    var deferred = false;

    final existingInbox = await _processInbox();
    if (existingInbox case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    inspected += (existingInbox as Success<_InboxProgress>).value.inspected;

    final existingAcks = await _flushAcknowledgements();
    if (existingAcks case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    acknowledged += (existingAcks as Success<int>).value;

    for (
      var pageIndex = 0;
      pageIndex < limits.maximumDrainPagesPerRun;
      pageIndex += 1
    ) {
      final drain = await _remote.drain(limit: limits.drainPageSize);
      if (drain case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final page = (drain as Success<DrainPage>).value;
      drainedPages += 1;
      final persisted = await _store.persistDrainPage(page);
      if (persisted case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }

      final inbox = await _processInbox();
      if (inbox case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final inboxProgress = (inbox as Success<_InboxProgress>).value;
      inspected += inboxProgress.inspected;

      final acks = await _flushAcknowledgements();
      if (acks case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final acknowledgedThisPage = (acks as Success<int>).value;
      acknowledged += acknowledgedThisPage;

      if (!page.hasMore) {
        break;
      }
      if (inboxProgress.inspected == 0 && acknowledgedThisPage == 0) {
        deferred = true;
        break;
      }
      if (pageIndex + 1 == limits.maximumDrainPagesPerRun) {
        deferred = true;
      }
    }

    for (var index = 0; index < limits.maximumOutboxBatchesPerRun; index += 1) {
      final now = _clock.now();
      final batchResult = await _store.beginNextOutboxBatch(now: now);
      if (batchResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final batch = (batchResult as Success<OutboxBatch?>).value;
      if (batch == null) {
        break;
      }
      final response = await _remote.send(batch);
      if (response case FailureResult(failure: final failure)) {
        if (_isPermanentSendFailure(failure)) {
          final recorded = await _store.recordOutboxPermanentFailure(
            batch: batch,
            now: now,
          );
          if (recorded case FailureResult(failure: final storageFailure)) {
            return Result.failure(storageFailure);
          }
          continue;
        }
        final retry = await _store.recordOutboxRetry(
          batch: batch,
          retryAt: now.add(
            retryPolicy.delayFor(
              attempt: batch.attempt,
              failure: failure,
              jitter: _jitter,
            ),
          ),
        );
        if (retry case FailureResult(failure: final storageFailure)) {
          return Result.failure(storageFailure);
        }
        return Result.failure(failure);
      }
      final acceptance = (response as Success<OutboxAcceptance>).value;
      if (!_isValidAcceptance(batch, acceptance)) {
        const failure = SecurityFailure(
          SecurityFailureKind.malformedServerResponse,
        );
        final retry = await _store.recordOutboxRetry(
          batch: batch,
          retryAt: now.add(
            retryPolicy.delayFor(
              attempt: batch.attempt,
              failure: failure,
              jitter: _jitter,
            ),
          ),
        );
        if (retry case FailureResult(failure: final storageFailure)) {
          return Result.failure(storageFailure);
        }
        return const Result.failure(failure);
      }
      final recorded = await _store.recordOutboxAcceptance(
        batch: batch,
        acceptance: acceptance,
        now: now,
      );
      if (recorded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      sent += acceptance.accepted;
      if (index + 1 == limits.maximumOutboxBatchesPerRun) {
        deferred = true;
      }
    }

    final refreshes = await _refreshStaleDevices();
    if (refreshes case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }

    final finishedAt = _clock.now();
    final recordedSync = await _store.recordSuccessfulSync(finishedAt);
    if (recordedSync case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final online = await _store.markConnectionPhase(SyncConnectionPhase.online);
    if (online case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return Result.success(
      SyncRunReport(
        drainedPages: drainedPages,
        inspectedEnvelopes: inspected,
        acknowledgedEnvelopes: acknowledged,
        sentTargets: sent,
        deferred: deferred,
      ),
    );
  }

  Future<Result<_InboxProgress>> _processInbox() async {
    var inspected = 0;
    var blocked = 0;
    for (var index = 0; index < limits.maximumInspectionsPerRun; index += 1) {
      final projection = await _store.readProjection();
      if (projection case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final gapBlocked =
          (projection as Success<SyncProjection>).value.queueGapState ==
          QueueGapState.recoveryRequired;
      final envelopeResult = await _store.beginNextEnvelopeInspection(
        now: _clock.now(),
      );
      if (envelopeResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final envelope = (envelopeResult as Success<SyncEnvelope?>).value;
      if (envelope == null) {
        break;
      }
      final inspection = await _inspector.inspect(
        envelopeId: envelope.id,
        exactCiphertext: envelope.exactCiphertext,
        allowPotentiallyMls: !gapBlocked,
      );
      if (inspection case FailureResult(failure: final failure)) {
        if (_isRejectableEnvelopeFailure(failure)) {
          final rejected = await _store.recordEnvelopeRejection(
            envelopeId: envelope.id,
            reasonCode: _rejectionReason(failure),
          );
          if (rejected case FailureResult(failure: final storageFailure)) {
            return Result.failure(storageFailure);
          }
          inspected += 1;
          continue;
        }
        final retry = await _store.recordEnvelopeInspectionRetry(
          envelopeId: envelope.id,
          retryAt: _clock.now().add(
            retryPolicy.delayFor(
              attempt: envelope.attempt,
              failure: failure,
              jitter: _jitter,
            ),
          ),
        );
        if (retry case FailureResult(failure: final storageFailure)) {
          return Result.failure(storageFailure);
        }
        return Result.failure(failure);
      }
      final inspectedEnvelope =
          (inspection as Success<OpaqueEnvelopeInspection>).value;
      if (gapBlocked &&
          inspectedEnvelope.dependency == EnvelopeDependency.potentiallyMls) {
        final blockedResult = await _store.blockEnvelopeForQueueGap(
          envelope.id,
        );
        if (blockedResult case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
        blocked += 1;
        continue;
      }
      final committed = await _store.commitOpaqueInspection(
        envelopeId: envelope.id,
        inspection: inspectedEnvelope,
      );
      if (committed case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      inspected += 1;
    }
    return Result.success(
      _InboxProgress(inspected: inspected, blocked: blocked),
    );
  }

  Future<Result<int>> _flushAcknowledgements() async {
    var acknowledged = 0;
    for (
      var index = 0;
      index < limits.maximumAcknowledgementBatchesPerRun;
      index += 1
    ) {
      final now = _clock.now();
      final batchResult = await _store.beginAcknowledgementBatch(
        now: now,
        maximumIds: 200,
      );
      if (batchResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final batch = (batchResult as Success<AcknowledgementBatch?>).value;
      if (batch == null) {
        break;
      }
      final response = await _remote.acknowledge(batch.envelopeIds);
      if (response case FailureResult(failure: final failure)) {
        final retry = await _store.recordAcknowledgementFailure(
          batch: batch,
          retryAt: now.add(
            retryPolicy.delayFor(
              attempt: batch.attempt,
              failure: failure,
              jitter: _jitter,
            ),
          ),
        );
        if (retry case FailureResult(failure: final storageFailure)) {
          return Result.failure(storageFailure);
        }
        return Result.failure(failure);
      }
      final recorded = await _store.recordAcknowledgementSuccess(
        batch: batch,
        now: now,
      );
      if (recorded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      acknowledged += batch.envelopeIds.length;
    }
    return Result.success(acknowledged);
  }

  Future<Result<void>> _refreshStaleDevices() async {
    final pending = await _store.pendingStaleDeviceRefreshes(now: _clock.now());
    if (pending case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    var count = 0;
    for (final work
        in (pending as Success<List<StaleDeviceRefreshWork>>).value) {
      if (count >= limits.maximumStaleRefreshesPerRun) {
        break;
      }
      count += 1;
      final refreshed = await _staleDeviceRefresh.refreshUserDevices(
        work.userId,
      );
      if (refreshed case FailureResult(failure: final failure)) {
        final retryAt = _clock.now().add(
          retryPolicy.delayFor(
            attempt: work.attempt,
            failure: failure,
            jitter: _jitter,
          ),
        );
        final recorded = await _store.retryStaleDeviceRefresh(
          userId: work.userId,
          retryAt: retryAt,
        );
        if (recorded case FailureResult(failure: final storageFailure)) {
          return Result.failure(storageFailure);
        }
        continue;
      }
      final completed = await _store.completeStaleDeviceRefresh(work.userId);
      if (completed case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
    }
    return const Result.success(null);
  }

  bool _isValidAcceptance(OutboxBatch batch, OutboxAcceptance acceptance) {
    final targetIds = batch.targets
        .map((target) => target.recipientDeviceId)
        .toSet();
    return targetIds.containsAll(acceptance.staleDeviceIds) &&
        acceptance.accepted ==
            batch.targets.length - acceptance.staleDeviceIds.length;
  }

  bool _isPermanentSendFailure(Failure failure) {
    if (failure is ValidationFailure) {
      return true;
    }
    return failure is BackendFailure &&
        const {
          BackendFailureCode.invalidRequest,
          BackendFailureCode.badRequest,
          BackendFailureCode.badBucket,
        }.contains(failure.code);
  }

  bool _isRejectableEnvelopeFailure(Failure failure) =>
      failure is ValidationFailure ||
      (failure is SecurityFailure &&
          failure.kind != SecurityFailureKind.policyBlocked);

  int _rejectionReason(Failure failure) => switch (failure.category) {
    FailureCategory.validation => 1,
    FailureCategory.security => 2,
    FailureCategory.unsupportedProtocol => 3,
    _ => 4,
  };
}

final class _InboxProgress {
  const _InboxProgress({required this.inspected, required this.blocked});

  final int inspected;
  final int blocked;
}
