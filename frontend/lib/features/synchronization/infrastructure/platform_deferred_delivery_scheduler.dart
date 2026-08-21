// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/infrastructure/sync_platform_adapters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android side of deferred delivery, behind one method channel.
///
/// Nothing about a message crosses it. Dart asks the platform to arm or disarm
/// a periodic job and to say whether a headless catch-up currently owns
/// delivery; the platform asks Dart to run one catch-up now and waits for the
/// answer. There is no payload in either direction beyond an interval in
/// milliseconds, so an entry point reached this way carries nothing a hostile
/// caller could shape.
///
/// The reply to `runCatchUp` is the load-bearing part. The platform holds a
/// wake lock for the duration of the job and lets the process be frozen again
/// once the job is finished, so a reply sent before the drain has finished ends
/// the catch-up mid-flight. This adapter therefore does not answer until the
/// delivery owner acknowledges the tick — or until [tickDeadline] passes, which
/// keeps a stalled owner from holding the wake-up open until the platform's own
/// deadline kills the process.
final class PlatformDeferredDeliveryScheduler
    implements AndroidPollingScheduler {
  PlatformDeferredDeliveryScheduler({
    MethodChannel channel = const MethodChannel(channelName),
    this.tickDeadline = const Duration(minutes: 2),
    this.ownershipDeadline = const Duration(minutes: 5),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  static const channelName = 'communication_platform/background_delivery';

  /// How long one deferred wake-up may take before this adapter stops waiting
  /// for the delivery owner and tells the platform the moment is over.
  ///
  /// Shorter than the platform's own job timeout on purpose: an answer this
  /// application chose is better than a stop the system imposes, because the
  /// system's is delivered by killing work wherever it stands.
  final Duration tickDeadline;

  /// How long a session may wait for exclusive ownership before it gives up and
  /// composes nothing.
  ///
  /// Longer than the deadline the platform applies to a headless run, so the
  /// ordinary end of a wait is that run finishing. Reaching this means the
  /// platform side stopped answering at all — in which case there is nothing
  /// running to race with either, but a session that cannot establish it is
  /// exclusive does not proceed as though it had.
  final Duration ownershipDeadline;

  final MethodChannel _channel;
  final StreamController<BestEffortDeliveryTick> _triggers =
      StreamController<BestEffortDeliveryTick>.broadcast();
  bool _disposed = false;

  @override
  Stream<BestEffortDeliveryTick> get foregroundTriggers => _triggers.stream;

  @override
  Future<void> scheduleBestEffort({required Duration minimumInterval}) =>
      _invoke('schedule', <String, Object?>{
        'minimumIntervalMillis': minimumInterval.inMilliseconds,
      });

  @override
  Future<void> cancel() => _invoke('cancel', const <String, Object?>{});

  @override
  Future<void> awaitExclusiveOwnership() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel
          .invokeMethod<void>(
            'awaitExclusiveOwnership',
            const <String, Object?>{},
          )
          .timeout(ownershipDeadline);
    } on MissingPluginException {
      // No implementation behind the channel, so nothing schedules anything and
      // there is no second owner this could be waiting for.
    } on PlatformException {
      // Same conclusion: the platform could not answer the question, and it is
      // also the thing that would have started the other owner.
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _channel.setMethodCallHandler(null);
    await _triggers.close();
  }

  Future<Object?> _onPlatformCall(MethodCall call) async {
    if (call.method != 'runCatchUp') {
      throw MissingPluginException('Unknown method ${call.method}.');
    }
    if (_disposed || !_triggers.hasListener) {
      // No delivery owner is listening in this isolate, so there is nothing to
      // wait for. Answering at once lets the platform release the process
      // instead of holding a wake-up open for work that will never start.
      return null;
    }
    final acknowledged = Completer<void>();
    _triggers.add(
      BestEffortDeliveryTick(
        onComplete: () {
          if (!acknowledged.isCompleted) {
            acknowledged.complete();
          }
        },
      ),
    );
    await acknowledged.future.timeout(tickDeadline, onTimeout: () {});
    return null;
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    // The check is on the target platform rather than on `dart:io`, because
    // this file must stay importable by a future Web build and because a test
    // has to be able to drive the Android path without an Android device.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No implementation behind the channel. Nothing is scheduled and nothing
      // pretends to be: the honest consequence is that a backgrounded build
      // performs no catch-up, which is what the caller's own state reports.
    } on PlatformException {
      // The platform refused. Same consequence, and the durable queue is
      // untouched either way.
    }
  }
}

/// What a headless catch-up tells the platform when it is done.
///
/// A deferred wake-up is a bounded moment the operating system granted, and the
/// process is frozen again once it is released. The Dart half of a headless run
/// is therefore responsible for saying that it has finished: the platform side
/// keeps the engine alive until then, and enforces its own deadline so a run
/// that never reports cannot hold the wake-up open indefinitely.
final class DeferredCatchUpHandshake {
  const DeferredCatchUpHandshake({
    MethodChannel channel = const MethodChannel(
      PlatformDeferredDeliveryScheduler.channelName,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Stops the periodic wake-up. Called by a headless run that found nothing to
  /// deliver to, so an application nobody is signed into stops being woken.
  Future<void> cancelSchedule() => _report('cancel');

  /// Reports that this headless run is over and its engine may be torn down.
  Future<void> reportFinished() => _report('finished');

  Future<void> _report(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method, const <String, Object?>{});
    } on MissingPluginException {
      // Nothing is hosting this run, so there is nothing to tear down.
    } on PlatformException {
      // The platform's own deadline is what ends the run instead.
    }
  }
}
