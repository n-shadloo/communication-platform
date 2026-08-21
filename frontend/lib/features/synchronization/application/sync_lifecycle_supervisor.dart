// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/synchronization/application/durable_sync_engine.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

final class SyncLifecycleSupervisor {
  SyncLifecycleSupervisor({
    required DurableSyncEngine engine,
    required DurableSyncStore store,
    required RealtimeSyncPort realtime,
    required NetworkAvailabilityPort network,
    required ApplicationLifecyclePort lifecycle,
    required BestEffortPollingPort polling,
    required TimeSource clock,
    required JitterSource jitter,
    required DelayPort delay,
    this.reconnectPolicy = const SyncRetryPolicy(
      baseDelay: Duration(seconds: 1),
      maximumDelay: Duration(minutes: 5),
    ),
    this.stableConnectionThreshold = const Duration(seconds: 30),
  }) : _engine = engine,
       _store = store,
       _realtime = realtime,
       _network = network,
       _lifecycle = lifecycle,
       _polling = polling,
       _clock = clock,
       _jitter = jitter,
       _delay = delay;

  final DurableSyncEngine _engine;
  final DurableSyncStore _store;
  final RealtimeSyncPort _realtime;
  final NetworkAvailabilityPort _network;
  final ApplicationLifecyclePort _lifecycle;
  final BestEffortPollingPort _polling;
  final TimeSource _clock;
  final JitterSource _jitter;
  final DelayPort _delay;
  final SyncRetryPolicy reconnectPolicy;
  final Duration stableConnectionThreshold;

  final StreamController<SyncProjection> _projections =
      StreamController<SyncProjection>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  StreamSubscription<SyncProjection>? _projectionSubscription;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _activeCycle;
  bool _cycleRequested = false;
  int _generation = 0;
  int _observedOutboxDepth = 0;

  Stream<SyncProjection> get projections => _projections.stream;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _projectionSubscription = _store.watchProjection().listen(
      _onProjection,
      onError: (_) {},
    );
    _subscriptions
      ..add(_network.changes.listen(_onNetworkChanged))
      ..add(_lifecycle.changes.listen(_onLifecycleChanged))
      ..add(_polling.triggers.listen(_onDeferredTick))
      ..add(
        _realtime.durableEnvelopeHints.listen((_) {
          unawaited(_recordHintAndDrain());
        }),
      )
      ..add(
        _realtime.disconnects.listen((event) {
          unawaited(_onRealtimeDisconnect(event));
        }),
      );

    if (_lifecycle.current == ApplicationExecutionState.foreground) {
      await _resumeForeground();
    } else {
      await _enterBackground();
    }
  }

  /// Runs one cycle for a deferred platform wake-up and then acknowledges it.
  ///
  /// The acknowledgement is unconditional and happens exactly once, including
  /// when the cycle failed or was refused because the network is unavailable.
  /// The scheduler is not asking whether delivery succeeded — it is asking
  /// whether this process may be let go, and a tick that is never acknowledged
  /// holds the wake-up open until the platform's own deadline kills it.
  void _onDeferredTick(BestEffortDeliveryTick tick) {
    unawaited(_requestCycle().whenComplete(tick.complete));
  }

  /// Turns growth of the durable outbox into a delivery cycle.
  ///
  /// Sending is not a call into this supervisor. A composer writes exact
  /// per-recipient ciphertext rows inside a Drift transaction and returns; the
  /// rows are the request. Nothing else in the lifecycle would notice them —
  /// socket hints announce *inbound* envelopes, and a foregrounded application
  /// with a healthy connection has no other reason to run — so without this a
  /// queued message would sit in local storage until an unrelated event
  /// happened to wake the engine.
  ///
  /// The trigger is the durable queue's depth *increasing*, which is what makes
  /// it both crash-safe and loop-safe. Crash-safe, because a restart replays
  /// the depth as the stream's first value and drains what was queued before
  /// the process died. Loop-safe, because every run of the engine writes a
  /// connection phase and so re-emits this projection: reacting to "depth is
  /// non-zero" would spin against a row waiting out its retry backoff, while
  /// reacting to "depth grew" cannot, since only a new durable target grows it.
  void _onProjection(SyncProjection projection) {
    _projections.add(projection);
    final previous = _observedOutboxDepth;
    _observedOutboxDepth = projection.outboxDepth;
    if (projection.outboxDepth > previous) {
      unawaited(_requestCycle());
    }
  }

  Future<void> _recordHintAndDrain() async {
    final recorded = await _store.requestAuthoritativeDrain();
    if (recorded is Success<void>) {
      await _requestCycle();
    }
  }

  void _onNetworkChanged(NetworkAvailability availability) {
    if (availability == NetworkAvailability.unavailable) {
      _generation += 1;
      unawaited(_realtime.close());
      unawaited(_store.markConnectionPhase(SyncConnectionPhase.offline));
      return;
    }
    if (_lifecycle.current == ApplicationExecutionState.foreground) {
      unawaited(_resumeForeground());
    } else {
      unawaited(_requestCycle());
    }
  }

  void _onLifecycleChanged(ApplicationExecutionState state) {
    if (state == ApplicationExecutionState.foreground) {
      unawaited(_resumeForeground());
    } else {
      unawaited(_enterBackground());
    }
  }

  Future<void> _resumeForeground() async {
    if (_disposed ||
        _network.current == NetworkAvailability.unavailable ||
        _lifecycle.current != ApplicationExecutionState.foreground) {
      return;
    }
    _generation += 1;
    final generation = _generation;
    final reconnect = await _store.readReconnectState();
    if (reconnect case Success(value: final state)) {
      final dueAt = state.dueAt;
      if (dueAt != null && dueAt.isAfter(_clock.now())) {
        unawaited(
          _waitThenReconnect(dueAt.difference(_clock.now()), generation),
        );
        return;
      }
    }
    await _connectAndDrain(generation);
  }

  /// Gives up the socket the moment the application stops being foregrounded.
  ///
  /// It does not arm or disarm the deferred catch-up. That is armed once for
  /// the whole signed-in session by whoever owns the session, because a
  /// periodic platform job restarts its window every time it is re-registered
  /// and a process that dies while foregrounded would otherwise leave nothing
  /// scheduled at all.
  Future<void> _enterBackground() async {
    _generation += 1;
    await _realtime.close();
    if (_lifecycle.current == ApplicationExecutionState.detached) {
      await _store.markConnectionPhase(SyncConnectionPhase.stopped);
    }
  }

  Future<void> _connectAndDrain(int generation) async {
    if (!_canUseRealtime(generation)) {
      return;
    }
    await _store.markConnectionPhase(SyncConnectionPhase.connecting);
    final connected = await _realtime.connect();
    if (!_canUseRealtime(generation)) {
      await _realtime.close();
      return;
    }
    if (connected case FailureResult(failure: final failure)) {
      await _requestCycle();
      await _scheduleReconnect(failure, generation);
      return;
    }
    unawaited(_markStableAfterDelay(generation));
    await _requestCycle();
  }

  Future<void> _markStableAfterDelay(int generation) async {
    await _delay.wait(stableConnectionThreshold);
    if (_canUseRealtime(generation)) {
      _realtime.markStableConnection();
      await _store.clearReconnect(syncedAt: null);
    }
  }

  /// Requests one delivery cycle, and completes when the work it asked for is
  /// over rather than when the request was accepted.
  ///
  /// A caller that already has a cycle in flight joins it instead of starting a
  /// second one, which is what lets a deferred platform wake-up wait for the
  /// real end of the drain even when a socket hint got there first.
  Future<void> _requestCycle() {
    if (_disposed || _network.current == NetworkAvailability.unavailable) {
      return Future<void>.value();
    }
    final active = _activeCycle;
    if (active != null) {
      _cycleRequested = true;
      return active;
    }
    final run = _runCycles();
    _activeCycle = run;
    return run;
  }

  Future<void> _runCycles() async {
    try {
      do {
        _cycleRequested = false;
        final result = await _engine.synchronize();
        if (result case FailureResult(failure: final failure)) {
          if (_lifecycle.current == ApplicationExecutionState.foreground) {
            await _scheduleReconnect(failure, _generation);
          }
          break;
        }
      } while (_cycleRequested && !_disposed);
    } finally {
      // Cleared here rather than from a callback on the returned future, so
      // that a request arriving in the microtask after this run finishes starts
      // a new cycle instead of joining a completed one and being dropped.
      _activeCycle = null;
    }
  }

  Future<void> _onRealtimeDisconnect(RealtimeDisconnect event) async {
    if (_disposed) {
      return;
    }
    switch (event.action) {
      case RealtimeRecoveryAction.stopRevoked:
        _generation += 1;
        await _store.markConnectionPhase(SyncConnectionPhase.revoked);
      case RealtimeRecoveryAction.openCircuit:
        _generation += 1;
        await _store.markConnectionPhase(
          SyncConnectionPhase.protocolCircuitOpen,
        );
      case RealtimeRecoveryAction.stopOriginRejected:
        _generation += 1;
        await _store.markConnectionPhase(SyncConnectionPhase.originRejected);
      case RealtimeRecoveryAction.refreshThenReconnectOnce:
        await _scheduleReconnect(
          const AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
          _generation,
          immediate: true,
        );
      case RealtimeRecoveryAction.reconnectWithBackoff:
        await _scheduleReconnect(
          const TransportFailure(TransportFailureKind.connectionRejected),
          _generation,
        );
      case RealtimeRecoveryAction.none:
        if (event.kind == RealtimeDisconnectKind.normal) {
          await _store.markConnectionPhase(SyncConnectionPhase.stopped);
        }
    }
  }

  Future<void> _scheduleReconnect(
    Failure failure,
    int generation, {
    bool immediate = false,
  }) async {
    if (!_canUseRealtime(generation)) {
      return;
    }
    final current = await _store.readReconnectState();
    final nextAttempt = switch (current) {
      Success(value: final state) => state.attempt + 1,
      _ => 1,
    };
    final delay = immediate
        ? Duration.zero
        : reconnectPolicy.delayFor(
            attempt: nextAttempt,
            failure: failure,
            jitter: _jitter,
          );
    final dueAt = _clock.now().add(delay);
    final persisted = await _store.scheduleReconnect(dueAt: dueAt);
    if (persisted is FailureResult<DurableReconnectState>) {
      return;
    }
    unawaited(_waitThenReconnect(delay, generation));
  }

  Future<void> _waitThenReconnect(Duration delay, int generation) async {
    await _delay.wait(delay);
    if (_canUseRealtime(generation)) {
      await _connectAndDrain(generation);
    }
  }

  bool _canUseRealtime(int generation) =>
      !_disposed &&
      generation == _generation &&
      _network.current == NetworkAvailability.available &&
      _lifecycle.current == ApplicationExecutionState.foreground;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _projectionSubscription?.cancel();
    _projectionSubscription = null;
    await _realtime.close();
    await _projections.close();
  }
}
