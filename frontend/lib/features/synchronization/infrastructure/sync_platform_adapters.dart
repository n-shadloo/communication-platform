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

  /// Re-reads the operating system's current answer.
  ///
  /// Required on resume rather than merely useful: connectivity_plus documents
  /// that on Android 8.0 and above "connectivity changes are no longer
  /// communicated to Android apps in the background" and that the app should
  /// "check the connectivity status when the app is resumed". Without this the
  /// cached value can say *unavailable* for a network that came back while the
  /// application was not in the foreground, and the supervisor's foreground
  /// resume would refuse to connect against a working network.
  Future<void> refresh() async {
    try {
      _onChanged(await _connectivity.checkConnectivity());
    } on Object {
      // A platform-channel failure leaves the last known value in place. This
      // never fabricates availability: the transport decides reachability, and
      // this port only stops it from trying when the OS says there is no
      // network at all.
    }
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
    final reported = WidgetsBinding.instance.lifecycleState;
    // `lifecycleState` is null until the first SystemChannels.lifecycle
    // message arrives, and Flutter documents the initial value as "the
    // detached state, updated to the current state (usually resumed) as soon
    // as the first lifecycle update is received from the platform". On Android
    // that message is not guaranteed to have arrived by the time the widget
    // tree is built, so mapping "not yet reported" onto background or detached
    // would make a session started at launch immediately stand itself down and
    // never open a socket. This code only runs because a Flutter view is
    // hosting it, so foreground is the truthful reading of "attached, nothing
    // reported yet"; the first real platform message corrects it either way.
    _current = reported == null
        ? ApplicationExecutionState.foreground
        : _map(reported);
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

  ApplicationExecutionState _map(AppLifecycleState state) => switch (state) {
    AppLifecycleState.resumed => ApplicationExecutionState.foreground,
    AppLifecycleState.detached => ApplicationExecutionState.detached,
    AppLifecycleState.inactive ||
    AppLifecycleState.hidden ||
    AppLifecycleState.paused => ApplicationExecutionState.background,
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

/// The polling port for a build with no background scheduler composed.
///
/// [AndroidPollingScheduler] still has no adapter: ADR-046's Layer 1 WorkManager
/// registration is a later piece of work. This is the honest stand-in for that
/// absence, and it deliberately does not pretend. It schedules nothing and emits
/// nothing, so a backgrounded application performs no catch-up at all, exactly
/// as the enrollment disclosure tells recipients. Queued work stays durable in
/// Drift and is drained the next time the application is foregrounded.
final class UnscheduledBestEffortPolling implements BestEffortPollingPort {
  const UnscheduledBestEffortPolling();

  @override
  Stream<void> get triggers => const Stream<void>.empty();

  @override
  Future<void> schedule({required Duration minimumInterval}) async {}

  @override
  Future<void> cancel() async {}
}

/// The platform edges of one delivery session on the version-1 Android target.
///
/// Resolving connectivity touches a platform channel and observing the
/// lifecycle touches the widget binding, so this is built once per session and
/// released with it. It also closes the gap connectivity_plus documents on
/// Android 8.0 and above, where background connectivity changes are not
/// delivered: every foreground transition re-reads the operating system's
/// answer rather than trusting a value cached from before the application was
/// backgrounded.
final class FlutterDeliveryPlatformPorts implements DeliveryPlatformPorts {
  FlutterDeliveryPlatformPorts._({
    required ConnectivityNetworkAvailabilityPort network,
    required FlutterApplicationLifecyclePort lifecycle,
  }) : _network = network,
       _lifecycle = lifecycle {
    _resumes = _lifecycle.changes.listen((state) {
      if (state == ApplicationExecutionState.foreground) {
        unawaited(_network.refresh());
      }
    });
  }

  static Future<FlutterDeliveryPlatformPorts> create({
    Connectivity? connectivity,
  }) async => FlutterDeliveryPlatformPorts._(
    network: await ConnectivityNetworkAvailabilityPort.create(
      connectivity: connectivity,
    ),
    lifecycle: FlutterApplicationLifecyclePort(),
  );

  final ConnectivityNetworkAvailabilityPort _network;
  final FlutterApplicationLifecyclePort _lifecycle;
  late final StreamSubscription<ApplicationExecutionState> _resumes;

  @override
  NetworkAvailabilityPort get network => _network;

  @override
  ApplicationLifecyclePort get lifecycle => _lifecycle;

  @override
  BestEffortPollingPort get polling => const UnscheduledBestEffortPolling();

  @override
  DelayPort get delay => const TimerDelayPort();

  @override
  Future<void> dispose() async {
    await _resumes.cancel();
    await _lifecycle.dispose();
    await _network.dispose();
  }
}
