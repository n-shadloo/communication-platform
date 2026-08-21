import 'dart:async';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/application_runtime.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/app/dependencies/message_alerts.dart';
import 'package:communication_platform/app/dependencies/sync_providers.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/application/reconcile_message_alerts.dart';
import 'package:communication_platform/features/notifications/infrastructure/drift_message_alert_store.dart';
import 'package:communication_platform/features/synchronization/infrastructure/platform_deferred_delivery_scheduler.dart';
import 'package:communication_platform/shared/infrastructure/time/system_time_source.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What one deferred catch-up concluded.
///
/// Every value is a fact about this run and none of them is a promise about the
/// next one. They exist to be asserted in tests and, in two cases, to decide
/// whether the periodic wake-up should keep happening at all.
enum DeferredCatchUpOutcome {
  /// A delivery cycle ran to completion against the server.
  delivered,

  /// A delivery cycle ran and failed. The durable queue is unchanged and the
  /// next wake-up tries again.
  cycleFailed,

  /// There is no device-bound session to deliver to. The wake-up disarms
  /// itself: signing in is what arms it again.
  noSession,

  /// The server could not be reached. Nothing is wrong with this device and the
  /// schedule stays armed.
  offline,

  /// Protected local state could not be opened. Nothing was read, nothing was
  /// written, and nothing was announced.
  storageUnavailable,

  /// This build carries no provisioning, so it has no server to reach.
  unprovisioned,
}

/// One deferred catch-up: open protected state, drain the mailbox once, bring
/// the shade into agreement with what committed, and stop.
///
/// This is the whole of what a backgrounded application does. It is not a
/// second delivery implementation: the engine, the store, the inspector, the
/// group stack and the alert reconciliation are the same objects the foreground
/// composes, resolved from the same [ApplicationRuntime], so the background path
/// cannot drift away from the foreground one or quietly compose a weaker
/// posture than it.
///
/// It deliberately opens **no socket**. A socket is a thing that is held, and
/// nothing holds anything here: the platform granted a bounded moment, and one
/// authoritative REST drain is what fits in it.
///
/// It also deliberately runs the alert pass even when the drain failed, because
/// messages committed by an earlier run may still never have been announced —
/// an alert is a projection of committed local state, not of this cycle.
Future<DeferredCatchUpOutcome> runDeferredDeliveryCatchUp(
  AppEnvironment environment, {
  DeferredCatchUpHandshake handshake = const DeferredCatchUpHandshake(),
}) async {
  final runtime = await ApplicationRuntime.create(
    environment,
    platform: BootstrapPlatform.android,
  );
  if (runtime.authentication == null) {
    await runtime.close();
    // A build with no provisioning has nothing to wake up for, ever.
    await handshake.cancelSchedule();
    return DeferredCatchUpOutcome.unprovisioned;
  }
  final container = runtime.container();
  try {
    final outcome = await _catchUp(runtime, container);
    if (deferredCatchUpDisarms(outcome)) {
      await handshake.cancelSchedule();
    }
    return outcome;
  } on Object {
    // A headless entry point may never propagate. Anything that escaped the
    // paths below is reported as the one thing that is certainly true: this run
    // delivered nothing, and durable state is whatever the last committed
    // transaction left.
    return DeferredCatchUpOutcome.cycleFailed;
  } finally {
    container.dispose();
    await runtime.close();
  }
}

/// Whether an outcome means the periodic wake-up should stop happening.
///
/// Only one does. A run that could not open storage, or could not reach the
/// server, says nothing about whether the next one will, and disarming on
/// either would turn a locked phone or a dropped connection into a permanent
/// end of background delivery. Having nobody to deliver to is different: it is
/// stable until the user signs in, and signing in is what arms this again.
bool deferredCatchUpDisarms(DeferredCatchUpOutcome outcome) =>
    outcome == DeferredCatchUpOutcome.noSession ||
    outcome == DeferredCatchUpOutcome.unprovisioned;

/// What a restored session means for a deferred catch-up, before it does
/// anything at all. Null means the run may proceed.
///
/// Every fail-closed decision this entry point makes is here, in one pure
/// function, so that all of them are decided by a host test rather than by a
/// device nobody has. None of them degrades: a run that cannot establish a
/// full, device-bound, set-up session concludes nothing rather than reaching
/// for a weaker path.
DeferredCatchUpOutcome? deferredCatchUpRefusal(
  Result<AccountSessionBoundary> restored,
) {
  final AccountSessionBoundary boundary;
  switch (restored) {
    case Success(value: final value):
      boundary = value;
    case FailureResult(failure: final failure):
      return switch (failure) {
        // Storage is unavailable: the device may be locked after a restart and
        // the credential-encrypted database key cannot be unwrapped. Nothing
        // degrades to a weaker path; the run simply concludes nothing.
        StorageFailure() => DeferredCatchUpOutcome.storageUnavailable,
        TransportFailure() => DeferredCatchUpOutcome.offline,
        _ => DeferredCatchUpOutcome.noSession,
      };
  }
  if (boundary.scope != AccountSessionScope.full ||
      !boundary.securitySetupComplete ||
      boundary.deviceId == null) {
    // The same bar the foreground applies before it composes a session. Waking
    // every interval to rediscover it would be a battery cost with no possible
    // benefit, so the wake-up stands itself down until a session exists.
    return DeferredCatchUpOutcome.noSession;
  }
  // A restore that fell back to the stored identity because the server could
  // not be reached. There is nothing to drain over a connection that is not
  // there.
  return boundary.offline ? DeferredCatchUpOutcome.offline : null;
}

Future<DeferredCatchUpOutcome> _catchUp(
  ApplicationRuntime runtime,
  ProviderContainer container,
) async {
  // Restoring is what establishes the session, and it is also the first thing
  // that touches protected storage. Everything this run needs — the database
  // key, the device-bound tokens, a refreshed access token — is behind it, and
  // a failure here is the honest end of the run rather than something to work
  // around.
  final restored = await runtime.authentication!.useCases.restore();
  final refusal = deferredCatchUpRefusal(restored);
  if (refusal != null) {
    return refusal;
  }
  final boundary = (restored as Success<AccountSessionBoundary>).value;
  final scope = (userId: boundary.userId, deviceId: boundary.deviceId!);
  final engine = await container.read(durableSyncEngineProvider(scope).future);
  final cycle = await engine.synchronize();
  await _reconcileAlerts(container);
  return cycle is Success
      ? DeferredCatchUpOutcome.delivered
      : DeferredCatchUpOutcome.cycleFailed;
}

Future<void> _reconcileAlerts(ProviderContainer container) async {
  try {
    final database = await container.read(localDatabaseProvider.future);
    await ReconcileMessageAlerts(
      store: DriftMessageAlertStore(database),
      presenter: container.read(messageAlertPresenterProvider),
      visible: const BackgroundVisibleConversation(),
      clock: const SystemTimeSource(),
      // A previous process may have left an alert in the shade that this one
      // knows nothing about. Starting from "possibly posted" is what lets this
      // pass withdraw one whose messages were read on another device.
    ).call(alertPosted: true);
  } on Object {
    // Alerting is the last thing this run does and the least important. A
    // failure here spends no durable marker, so the next pass — in this process
    // or the next one — reaches the same conclusion.
  }
}

/// Nothing is on screen during a deferred catch-up, and no activity exists.
///
/// The second half matters more than the first. `ReconcileMessageAlerts` asks
/// for the notification permission at the point of use, once, and only while
/// the application is foregrounded, because the prompt belongs to an activity
/// the user is looking at. Reporting the truth here is what keeps a headless
/// run from spending that one automatic prompt into a context that has no
/// activity to show it in.
final class BackgroundVisibleConversation implements VisibleConversationPort {
  const BackgroundVisibleConversation();

  @override
  String? get conversationId => null;

  @override
  bool get isForeground => false;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// Runs one deferred catch-up and reports to the platform when it is over.
///
/// This is what a headless Dart entry point calls, and it is deliberately the
/// only thing that reports completion: the platform keeps the engine hosting
/// this isolate alive until it does, so a path that returned without reporting
/// would be torn down by the platform's deadline instead.
Future<DeferredCatchUpOutcome> runDeferredDeliveryEntryPoint(
  AppEnvironment environment, {
  DeferredCatchUpHandshake handshake = const DeferredCatchUpHandshake(),
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    return await runDeferredDeliveryCatchUp(environment, handshake: handshake);
  } finally {
    await handshake.reportFinished();
  }
}
