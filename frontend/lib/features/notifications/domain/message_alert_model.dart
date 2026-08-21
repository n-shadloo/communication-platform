/// Whether the platform will actually show an alert.
///
/// Three states, because three is what the platform can be asked without
/// guessing. Android reports whether notifications are enabled, but
/// `shouldShowRequestPermissionRationale` is false both before the first
/// request and after a permanent refusal, so an application that claimed to
/// distinguish "never asked" from "refused twice" would be making it up. What
/// can be asked instead - may this application spend its one automatic prompt -
/// is a separate question with its own answer.
enum MessageAlertAuthorization {
  /// Notifications are enabled for this application.
  granted,

  /// They are not, for whatever reason. Nothing is posted.
  withheld,

  /// No alert implementation is composed - a host without the platform channel,
  /// or a build that does not target Android. Nothing is posted and nothing
  /// pretends otherwise.
  unavailable,
}

/// The raw facts the platform reports, before any policy is applied to them.
///
/// The platform cannot decide [MessageAlertAuthorization] on its own:
/// `shouldShowRequestPermissionRationale` is false both before the first
/// request and after a permanent denial, so "never asked" and "asked twice and
/// refused" are indistinguishable without the application's own durable record
/// of whether it has ever asked.
final class MessageAlertPlatformState {
  const MessageAlertPlatformState({
    required this.enabled,
    required this.runtimePermission,
    required this.rationale,
  });

  /// `NotificationManagerCompat.areNotificationsEnabled()`.
  final bool enabled;

  /// Whether this platform version gates notifications behind a runtime
  /// permission at all - `POST_NOTIFICATIONS`, Android 13 (API 33) and above.
  final bool runtimePermission;

  /// `shouldShowRequestPermissionRationale(POST_NOTIFICATIONS)`.
  final bool rationale;

  /// Whether the application may spend its one automatic prompt.
  ///
  /// Two guards, because they close different holes. [everRequested] is this
  /// application's own durable record and is what stops a prompt from being
  /// repeated on every launch. [rationale] is Android's record, and it is true
  /// in exactly one situation - the user has refused once and not yet twice -
  /// so honouring it means an automatic prompt can never be the refusal that
  /// makes the denial permanent. Between them, a refusal the user made from
  /// Settings is respected even though Settings writes no marker.
  bool automaticPromptAllowed({required bool everRequested}) =>
      !enabled && runtimePermission && !everRequested && !rationale;

  MessageAlertAuthorization get authorization => enabled
      ? MessageAlertAuthorization.granted
      : MessageAlertAuthorization.withheld;
}

/// What one alert says.
///
/// There is exactly one alert and it names nothing: not the sender, not the
/// conversation, not a word of the message. The only thing that varies is
/// grammatical number, because "New message" and "New messages" are the same
/// disclosure and one of them is a lie.
enum MessageAlertBody { oneMessage, manyMessages }

/// One message that is unread on this device and may or may not have been
/// alerted yet.
final class PendingMessageAlert {
  const PendingMessageAlert({
    required this.messageId,
    required this.conversationId,
    required this.alerted,
    required this.mutedUntil,
  });

  final String messageId;
  final String conversationId;

  /// Whether the durable one-shot marker has already been spent.
  final bool alerted;

  /// The conversation's mute deadline, evaluated against the reconciler's
  /// clock rather than in SQL so a stream does not freeze "now" at the moment
  /// it was created.
  final DateTime? mutedUntil;

  bool isMuted(DateTime now) {
    final until = mutedUntil;
    return until != null && until.isAfter(now);
  }
}

/// What one reconciliation pass concluded, kept as a value so a test can assert
/// the decision rather than infer it from platform side effects.
final class MessageAlertOutcome {
  const MessageAlertOutcome({
    required this.authorization,
    required this.shown,
    required this.hidden,
    required this.body,
    required this.markedAlerted,
    required this.requested,
  });

  /// A pass that concluded nothing, because durable state could not be read.
  static const idle = MessageAlertOutcome(
    authorization: null,
    shown: false,
    hidden: false,
    body: null,
    markedAlerted: 0,
    requested: false,
  );

  /// `null` when the pass had no reason to ask the platform anything. Absence
  /// of an answer is recorded as absence, never as [MessageAlertAuthorization
  /// .unavailable], which is a different and much worse claim.
  final MessageAlertAuthorization? authorization;

  /// An alert was posted, and it alerted.
  final bool shown;

  /// The alert was withdrawn because nothing is outstanding any more.
  final bool hidden;

  /// The body posted, when [shown].
  final MessageAlertBody? body;

  /// How many messages had their durable marker spent in this pass.
  final int markedAlerted;

  /// Whether this pass asked the operating system for permission.
  final bool requested;
}
