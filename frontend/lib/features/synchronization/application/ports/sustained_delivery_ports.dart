import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/synchronization/domain/sustained_delivery_model.dart';

/// The operating-system side of sustained delivery, reduced to what this
/// application actually needs from it.
///
/// No policy lives behind this port. The platform reports facts, shows the two
/// dialogs only the operating system can show, and starts or stops one service;
/// every decision about whether to ask, in what order, and what to conclude
/// from the answer is Dart, so it is decided by a host test rather than by a
/// device nobody has.
///
/// Nothing crosses this boundary but booleans. There is no message, no
/// identifier, no token and no text, so a build with a hostile implementation
/// behind the channel would learn nothing it does not already know from the
/// package being installed.
abstract interface class SustainedDeliveryPlatformPort implements Port {
  /// The platform's current answer. Returns `null` when no implementation is
  /// composed, which callers treat as *unavailable* rather than as a
  /// permissive default.
  Future<SustainedDeliveryPlatformState?> platformState();

  /// Shows the system's own battery-optimization exemption dialog and
  /// completes when it closes. The answer is read back from
  /// `isIgnoringBatteryOptimizations()`, never from the dialog's own result,
  /// which reports dismissal and refusal identically.
  ///
  /// Must only be called while an activity is in the foreground.
  Future<SustainedDeliveryPlatformState?> requestExemption();

  /// Starts the foreground service, and answers with the state observed
  /// afterwards so the caller never has to assume it worked.
  Future<SustainedDeliveryPlatformState?> start();

  /// Stops it, and withdraws its notification with it. Idempotent, and
  /// harmless when nothing is running.
  Future<SustainedDeliveryPlatformState?> stop();

  /// Opens the manufacturer's own background-restriction screen for this
  /// application when the manufacturer documents one, and this device's
  /// application-details screen otherwise.
  ///
  /// It returns nothing on purpose. The application cannot read any of these
  /// settings, so it can never report what the user did there, and a surface
  /// that appeared to confirm it would be inventing the confirmation.
  Future<void> openVendorSettings();
}

/// Where the user's choice lives, so that it survives a restart and an update.
///
/// It is one row in the same SQLCipher-encrypted preferences table every other
/// durable preference uses. Deliberately not a plaintext file or a shared
/// preference: it is a fact about its owner, and it belongs behind the same key
/// as everything else that is.
abstract interface class SustainedDeliveryStorePort implements Port {
  Future<Result<bool>> readEnabled();

  Future<Result<void>> writeEnabled({required bool enabled});
}

/// Whether the delivery owner may keep its connection open while the
/// application is not in the foreground.
///
/// The default answer is no, and it is no for a reason the platform states: a
/// backgrounded process is cached, a cached process is frozen, and the system
/// terminates the TCP sockets of a frozen app. Only a running foreground
/// service changes that, so only a genuinely running one may change this
/// answer.
abstract interface class BackgroundConnectionPolicy implements Port {
  bool get mayHoldWhileBackgrounded;

  /// Fires whenever the answer changes, so a supervisor that is already
  /// backgrounded opens or closes its connection instead of waiting for an
  /// unrelated lifecycle event.
  Stream<void> get changes;
}

/// The policy for every composition without sustained delivery: never hold.
final class NeverHoldsInBackground implements BackgroundConnectionPolicy {
  const NeverHoldsInBackground();

  @override
  bool get mayHoldWhileBackgrounded => false;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}
