// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:communication_platform/features/synchronization/application/ports/sustained_delivery_ports.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/platform_sustained_delivery_port.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the sustained-delivery isolate says to the platform, and what the
/// platform says back to it.
///
/// Two directions, one channel. The platform asks this run to [standDown]
/// because a foreground engine is attaching and will hold the connection
/// itself; the run answers by finishing, which is also what it reports when it
/// ends for any other reason.
///
/// It *is* the [DeliveryStandDownSignal] the durable engine reads, rather than
/// something that maps onto one, so what the platform said and what the engine
/// sees cannot drift apart through a translation layer (ADR-050).
final class SustainedDeliveryHandshake implements DeliveryStandDownSignal {
  SustainedDeliveryHandshake({
    MethodChannel channel = const MethodChannel(
      PlatformSustainedDeliveryPort.channelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;
  final Completer<void> _standDown = Completer<void>();

  /// Once true, always true. A run that has been displaced is not un-displaced
  /// by anything the platform could say next.
  @override
  bool get standDownRequested => _standDown.isCompleted;

  /// Completes when this run is no longer the delivery owner.
  Future<void> get displaced => _standDown.future;

  /// Starts listening, before anything else happens, so a foreground engine
  /// attaching one millisecond later is heard rather than missed.
  void listen() => _channel.setMethodCallHandler(_onPlatformCall);

  void release() => _channel.setMethodCallHandler(null);

  /// Asks the platform to displace this run without waiting to be displaced.
  ///
  /// Used when the run concludes there is nothing to deliver to — the choice is
  /// off, or the session has ended — so that the service, and its permanent
  /// entry in the shade, stop with it.
  Future<void> stopService() => _report('stop');

  /// Reports that this run is over and its engine may be torn down.
  Future<void> reportFinished() => _report('finished');

  Future<Object?> _onPlatformCall(MethodCall call) async {
    if (call.method != 'standDown') {
      throw MissingPluginException('Unknown method ${call.method}.');
    }
    if (!_standDown.isCompleted) {
      _standDown.complete();
    }
    return null;
  }

  Future<void> _report(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, const <String, Object?>{});
    } on MissingPluginException {
      // Nothing is hosting this run, so there is nothing to tear down.
    } on PlatformException {
      // The platform could not act on it. The run ends either way.
    }
  }
}

/// The application lifecycle, as a sustained-delivery run genuinely sees it.
///
/// It reports *background* and never changes, because that is the truth: nobody
/// is looking at this application, and this isolate exists precisely because
/// nobody is. What makes a connection permissible here is not a foreground
/// state it does not have — it is the running foreground service that keeps
/// this process out of the cached state, and that is reported separately by
/// [AlwaysHoldsInBackground].
final class BackgroundedExecution implements ApplicationLifecyclePort {
  const BackgroundedExecution();

  @override
  ApplicationExecutionState get current => ApplicationExecutionState.background;

  @override
  Stream<ApplicationExecutionState> get changes =>
      const Stream<ApplicationExecutionState>.empty();
}

/// The connection policy inside a sustained-delivery run.
///
/// Always yes, and correctly so: this isolate is started by the foreground
/// service and destroyed when it stops, so for the whole of its life the
/// process is not cached and its sockets are not the platform's to terminate.
final class AlwaysHoldsInBackground implements BackgroundConnectionPolicy {
  const AlwaysHoldsInBackground();

  @override
  bool get mayHoldWhileBackgrounded => true;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}
