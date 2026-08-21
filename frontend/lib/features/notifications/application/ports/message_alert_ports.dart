import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';

/// The operating system's notification surface, reduced to the four things
/// this application needs from it.
///
/// No policy lives behind this port. The platform reports facts and performs
/// posts; every decision about whether to alert, what it says, and when to ask
/// for permission is Dart, so it is testable without a device.
abstract interface class MessageAlertPresenterPort implements Port {
  /// The platform's current answer, unresolved. Returns `null` when no
  /// implementation is composed.
  Future<MessageAlertPlatformState?> platformState();

  /// Shows the system permission prompt and completes when it is answered.
  /// Must only be called while an activity is in the foreground.
  Future<MessageAlertPlatformState?> requestPermission();

  /// Posts or updates the single message alert, alerting the user.
  Future<void> show(MessageAlertBody body);

  /// Withdraws it. Idempotent, and harmless when nothing is posted.
  Future<void> hide();

  /// Opens the operating system's notification settings for this application,
  /// which is the only place a [MessageAlertAuthorization.blocked] state can be
  /// changed.
  Future<void> openSystemSettings();
}

/// The durable local state one alert is a projection of.
abstract interface class MessageAlertStorePort implements Port {
  /// Fires once per committed write that could change the answer. It carries no
  /// data: the reconciler re-reads with a fresh clock, because mute deadlines
  /// are wall-clock and a bound query variable would freeze "now".
  Stream<void> get changes;

  /// Every message that is unread on this device and still displayable:
  /// incoming, not deleted for me, not withdrawn by its sender, and not in
  /// Saved Messages. Bounded by [limit].
  Future<Result<List<PendingMessageAlert>>> readPending({required int limit});

  /// Spends the one-shot marker. Written after a successful post, never before,
  /// so a crash in between costs one repeated alert rather than a silent loss.
  Future<Result<void>> markAlerted(List<String> messageIds);

  /// Whether this installation has ever shown the system permission prompt.
  /// Durable, because Android cannot distinguish "never asked" from "refused
  /// twice" and an application that re-asks every launch is the nag the
  /// platform's two-strike rule punishes.
  Future<Result<bool>> readPermissionRequested();

  Future<Result<void>> recordPermissionRequested();
}

/// Which conversation the user is looking at right now, or `null`.
///
/// A message that arrives into the conversation on screen has already made the
/// user aware of itself; alerting for it would be telling them something they
/// can see. "On screen" means both that the route is mounted and that the
/// application is in the foreground - a chat route left mounted behind a
/// backgrounded application is not something anyone is looking at.
abstract interface class VisibleConversationPort implements Port {
  String? get conversationId;

  /// Whether the application is in the foreground at all. Permission prompts
  /// need an activity the user is looking at, so this gates asking.
  bool get isForeground;

  Stream<void> get changes;
}
