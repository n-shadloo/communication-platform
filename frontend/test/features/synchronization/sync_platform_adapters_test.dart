import 'dart:async';

import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/sync_platform_adapters.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unreported platform lifecycle state is not treated as background', () {
    // What the binding looks like before the first SystemChannels.lifecycle
    // message, which on Android is not guaranteed to have arrived by the time
    // the widget tree is built. Reading it as background or detached would make
    // a session started at launch stand itself down and never open a socket.
    SchedulerBinding.instance.resetInternalState();
    expect(WidgetsBinding.instance.lifecycleState, isNull);

    final port = FlutterApplicationLifecyclePort();
    addTearDown(port.dispose);

    expect(port.current, ApplicationExecutionState.foreground);
  });

  test('reported platform states map to execution states', () async {
    SchedulerBinding.instance.resetInternalState();
    final port = FlutterApplicationLifecyclePort();
    addTearDown(port.dispose);
    final seen = <ApplicationExecutionState>[];
    final subscription = port.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    port.didChangeAppLifecycleState(AppLifecycleState.paused);
    port.didChangeAppLifecycleState(AppLifecycleState.resumed);
    port.didChangeAppLifecycleState(AppLifecycleState.detached);
    await pumpEvents();

    expect(seen, [
      ApplicationExecutionState.background,
      ApplicationExecutionState.foreground,
      ApplicationExecutionState.detached,
    ]);
  });

  test('refresh re-reads connectivity the platform changed silently', () async {
    final connectivity = FakeConnectivity([ConnectivityResult.wifi]);
    final port = await ConnectivityNetworkAvailabilityPort.create(
      connectivity: connectivity,
    );
    addTearDown(port.dispose);
    final seen = <NetworkAvailability>[];
    final subscription = port.changes.listen(seen.add);
    addTearDown(subscription.cancel);
    expect(port.current, NetworkAvailability.available);

    // Android 8.0 and above does not deliver connectivity changes to a
    // backgrounded app, so the cached answer can be stale on resume with no
    // event ever arriving on the stream.
    connectivity.results = [ConnectivityResult.none];
    await port.refresh();
    await pumpEvents();

    expect(port.current, NetworkAvailability.unavailable);
    expect(seen, [NetworkAvailability.unavailable]);
  });

  test('a platform-channel failure leaves the last known answer', () async {
    final connectivity = FakeConnectivity([ConnectivityResult.mobile]);
    final port = await ConnectivityNetworkAvailabilityPort.create(
      connectivity: connectivity,
    );
    addTearDown(port.dispose);

    connectivity.failing = true;
    await port.refresh();

    expect(port.current, NetworkAvailability.available);
  });

  test('the composed platform bundle refreshes network on resume', () async {
    SchedulerBinding.instance.resetInternalState();
    final connectivity = FakeConnectivity([ConnectivityResult.wifi]);
    final ports = await FlutterDeliveryPlatformPorts.create(
      connectivity: connectivity,
    );
    addTearDown(ports.dispose);
    expect(ports.network.current, NetworkAvailability.available);

    connectivity.results = [ConnectivityResult.none];
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await pumpEvents();

    expect(ports.network.current, NetworkAvailability.unavailable);
  });

  test(
    'the composed bundle schedules no background work in this build',
    () async {
      SchedulerBinding.instance.resetInternalState();
      final ports = await FlutterDeliveryPlatformPorts.create(
        connectivity: FakeConnectivity([ConnectivityResult.wifi]),
      );
      addTearDown(ports.dispose);
      final triggers = <void>[];
      final subscription = ports.polling.triggers.listen(triggers.add);
      addTearDown(subscription.cancel);

      // ADR-046 Layer 1 is not built. The port exists so the supervisor composes,
      // and it must not behave as though a scheduler were installed.
      await ports.polling.schedule(
        minimumInterval: const Duration(minutes: 15),
      );
      await ports.polling.cancel();
      await pumpEvents();

      expect(triggers, isEmpty);
    },
  );
}

final class FakeConnectivity implements Connectivity {
  FakeConnectivity(this.results);

  List<ConnectivityResult> results;
  bool failing = false;
  // ignore: close_sinks
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (failing) {
      throw StateError('platform channel unavailable');
    }
    return results;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

Future<void> pumpEvents() async {
  for (var index = 0; index < 8; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
