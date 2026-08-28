// ignore_for_file: prefer_initializing_formals

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/synchronization/application/ports/sustained_delivery_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sustained_delivery_model.dart';

/// Turning notifications on, when the platform will announce nothing without
/// them.
///
/// Declared here rather than imported from the notifications feature because a
/// feature's application layer may reach only its own layers and `core`. The
/// composition root adapts the one implementation that exists to this, so the
/// artifact still contains exactly one notification-permission path.
abstract interface class SustainedDeliveryAlertGate implements Port {
  /// Asks for the notification permission and answers with what the platform
  /// says afterwards. False covers refusal, dismissal, and a platform that
  /// cannot ask at all.
  Future<bool> ensureAlertsEnabled();
}

/// What turning sustained delivery on concluded.
///
/// A sealed outcome rather than a `Result`, because none of these is an error:
/// each is an answer the user or the platform gave, and the surface says a
/// different true sentence for each one.
sealed class SustainedDeliveryEnableOutcome {
  const SustainedDeliveryEnableOutcome();
}

final class SustainedDeliveryEnabled extends SustainedDeliveryEnableOutcome {
  const SustainedDeliveryEnabled(this.state);

  final SustainedDeliveryPlatformState state;
}

final class SustainedDeliveryRefused extends SustainedDeliveryEnableOutcome {
  const SustainedDeliveryRefused(this.refusal);

  final SustainedDeliveryRefusal refusal;
}

/// Turning sustained delivery on, once, deliberately, with the user present.
///
/// The order is not arbitrary. Notifications come first because a connection
/// held for messages the user is never told about is a battery cost with no
/// benefit, and because asking for the harder thing first would spend the
/// user's attention on the wrong question. The durable choice is recorded
/// before the service is started and withdrawn again if it will not start, so
/// what is stored and what is running never disagree.
///
/// Every exit that is not [SustainedDeliveryEnabled] leaves the application
/// exactly as it found it: nothing running, nothing held, and no durable choice
/// recorded.
final class EnableSustainedDelivery {
  const EnableSustainedDelivery({
    required SustainedDeliveryPlatformPort platform,
    required SustainedDeliveryStorePort store,
    required SustainedDeliveryAlertGate alerts,
  }) : _platform = platform,
       _store = store,
       _alerts = alerts;

  final SustainedDeliveryPlatformPort _platform;
  final SustainedDeliveryStorePort _store;
  final SustainedDeliveryAlertGate _alerts;

  Future<SustainedDeliveryEnableOutcome> call() async {
    var state = await _platform.platformState();
    if (state == null || !state.supported) {
      return const SustainedDeliveryRefused(
        SustainedDeliveryRefusal.unavailable,
      );
    }
    if (!state.alertsEnabled) {
      await _alerts.ensureAlertsEnabled();
      state = await _platform.platformState();
      if (state == null || !state.alertsEnabled) {
        return const SustainedDeliveryRefused(
          SustainedDeliveryRefusal.alertsRefused,
        );
      }
    }
    if (!state.exempt) {
      // The system's own dialog. Whatever it returns is discarded on purpose:
      // it reports dismissal and refusal identically, so the only trustworthy
      // answer is what `isIgnoringBatteryOptimizations()` says afterwards.
      state = await _platform.requestExemption() ?? state;
      if (!state.exempt) {
        return const SustainedDeliveryRefused(
          SustainedDeliveryRefusal.exemptionRefused,
        );
      }
    }
    final recorded = await _store.writeEnabled(enabled: true);
    if (recorded is FailureResult<void>) {
      return const SustainedDeliveryRefused(
        SustainedDeliveryRefusal.notRecorded,
      );
    }
    final started = await _platform.start();
    if (started == null || !started.running) {
      // The service would not start — the manufacturer-restriction case among
      // others. The choice is withdrawn rather than left recorded, so a later
      // launch does not silently retry what the user was just told failed.
      await _store.writeEnabled(enabled: false);
      await _platform.stop();
      return const SustainedDeliveryRefused(
        SustainedDeliveryRefusal.platformRefused,
      );
    }
    return SustainedDeliveryEnabled(started);
  }
}

/// Turning it off, completely.
///
/// The durable choice is cleared first and the service stopped second, so a
/// failure between them leaves a recorded *off* with a service still running —
/// which the next reconciliation stops — rather than a recorded *on* with
/// nothing running, which it would restart.
final class DisableSustainedDelivery {
  const DisableSustainedDelivery({
    required SustainedDeliveryPlatformPort platform,
    required SustainedDeliveryStorePort store,
  }) : _platform = platform,
       _store = store;

  final SustainedDeliveryPlatformPort _platform;
  final SustainedDeliveryStorePort _store;

  /// Answers with the status observed afterwards. [SustainedDeliveryStatus.off]
  /// is the only success; anything else means the choice could not be cleared.
  Future<SustainedDeliveryStatus> call() async {
    final recorded = await _store.writeEnabled(enabled: false);
    if (recorded is FailureResult<void>) {
      return SustainedDeliveryStatus.unavailable;
    }
    final state = await _platform.stop();
    return state?.statusFor(chosen: false) ?? SustainedDeliveryStatus.off;
  }
}

/// Brings the running state into agreement with the recorded choice and with
/// what the platform currently permits.
///
/// This is the only thing that starts the service outside the enable flow, and
/// it never asks the user for anything: a restore that showed a dialog would be
/// a launch that interrogates people who chose nothing.
///
/// It also *stops* the service whenever the arrangement is incomplete. A
/// service running without the exemption, or without notifications, keeps the
/// process alive for a connection this application will not hold and an alert
/// it cannot post — battery spent, and a permanent entry displayed, for
/// nothing.
final class ReconcileSustainedDelivery {
  const ReconcileSustainedDelivery({
    required SustainedDeliveryPlatformPort platform,
    required SustainedDeliveryStorePort store,
  }) : _platform = platform,
       _store = store;

  final SustainedDeliveryPlatformPort _platform;
  final SustainedDeliveryStorePort _store;

  Future<SustainedDeliveryStatus> call() async {
    final state = await _platform.platformState();
    if (state == null || !state.supported) {
      return SustainedDeliveryStatus.unavailable;
    }
    final chosen = switch (await _store.readEnabled()) {
      Success(value: final value) => value,
      // Storage that cannot be read is not evidence of a choice. Reading it as
      // *off* is what keeps an unavailable database from starting a service
      // the user may never have asked for.
      _ => false,
    };
    final status = state.statusFor(chosen: chosen);
    if (status == SustainedDeliveryStatus.stopped) {
      final started = await _platform.start();
      return (started ?? state).statusFor(chosen: chosen);
    }
    if (!status.holdsConnection && state.running) {
      final stopped = await _platform.stop();
      return (stopped ?? state).statusFor(chosen: chosen);
    }
    return status;
  }
}
