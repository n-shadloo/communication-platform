// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

final class FullJitterSource implements JitterSource {
  FullJitterSource([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  @override
  int nextInt(int upperBoundExclusive) => _random.nextInt(upperBoundExclusive);
}

final class TimerDelayPort implements DelayPort {
  const TimerDelayPort();

  @override
  Future<void> wait(Duration delay) => Future<void>.delayed(delay);
}

final class ConnectivityNetworkAvailabilityPort
    implements NetworkAvailabilityPort {
  ConnectivityNetworkAvailabilityPort._({
    required Connectivity connectivity,
    required NetworkAvailability initial,
  }) : _connectivity = connectivity,
       _current = initial {
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
  }

  static Future<ConnectivityNetworkAvailabilityPort> create({
    Connectivity? connectivity,
  }) async {
    final adapter = connectivity ?? Connectivity();
    final initial = await adapter.checkConnectivity();
    return ConnectivityNetworkAvailabilityPort._(
      connectivity: adapter,
      initial: _mapConnectivity(initial),
    );
  }

  final Connectivity _connectivity;
  final StreamController<NetworkAvailability> _changes =
      StreamController<NetworkAvailability>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  NetworkAvailability _current;

  @override
  NetworkAvailability get current => _current;

  @override
  Stream<NetworkAvailability> get changes => _changes.stream;

  void _onChanged(List<ConnectivityResult> results) {
    final next = _mapConnectivity(results);
    if (next != _current) {
      _current = next;
      _changes.add(next);
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _changes.close();
  }

  static NetworkAvailability _mapConnectivity(
    List<ConnectivityResult> results,
  ) =>
      results.isEmpty ||
          results.every((result) => result == ConnectivityResult.none)
      ? NetworkAvailability.unavailable
      : NetworkAvailability.available;
}

final class FlutterApplicationLifecyclePort
    with WidgetsBindingObserver
    implements ApplicationLifecyclePort {
  FlutterApplicationLifecyclePort() {
    WidgetsBinding.instance.addObserver(this);
    _current = _map(WidgetsBinding.instance.lifecycleState);
  }

  final StreamController<ApplicationExecutionState> _changes =
      StreamController<ApplicationExecutionState>.broadcast();
  late ApplicationExecutionState _current;
  bool _disposed = false;

  @override
  ApplicationExecutionState get current => _current;

  @override
  Stream<ApplicationExecutionState> get changes => _changes.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final next = _map(state);
    if (!_disposed && next != _current) {
      _current = next;
      _changes.add(next);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _changes.close();
  }

  ApplicationExecutionState _map(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.resumed => ApplicationExecutionState.foreground,
    AppLifecycleState.detached => ApplicationExecutionState.detached,
    AppLifecycleState.inactive ||
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    null => ApplicationExecutionState.background,
  };
}

/// Platform scheduling boundary for Android WorkManager integration.
///
/// The scheduler never promises an exact interval. A headless callback must construct
/// its own database/network dependencies and invoke the same durable engine; no state
/// from the foreground isolate is assumed to survive. Android implementations must
/// request WorkManager's connected-network constraint rather than waking to probe a
/// public host.
abstract interface class AndroidPollingScheduler {
  Stream<void> get foregroundTriggers;

  Future<void> scheduleBestEffort({required Duration minimumInterval});

  Future<void> cancel();
}

final class AndroidBestEffortPollingPort implements BestEffortPollingPort {
  const AndroidBestEffortPollingPort(this.scheduler);

  final AndroidPollingScheduler scheduler;

  @override
  Stream<void> get triggers => scheduler.foregroundTriggers;

  @override
  Future<void> schedule({required Duration minimumInterval}) =>
      scheduler.scheduleBestEffort(minimumInterval: minimumInterval);

  @override
  Future<void> cancel() => scheduler.cancel();
}
