import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';

/// Brings the one system alert into agreement with committed local state.
///
/// This is a reconciliation, not an emission. Each pass derives what the shade
/// *should* hold from durable rows and applies the difference, which is what
/// makes every hard case fall out of one rule instead of needing its own:
/// a message read on another device stops being outstanding and the alert is
/// withdrawn; a message its sender withdrew stops being displayable and does
/// the same; the conversation on screen contributes nothing; and re-observing
/// the same row cannot alert twice because the durable marker is already spent.
///
/// It never sees a transport event, an envelope, or a socket frame. Its whole
/// input is rows the inbox transaction has already committed.
final class ReconcileMessageAlerts {
  const ReconcileMessageAlerts({
    required this.store,
    required this.presenter,
    required this.visible,
    required this.clock,
    this.limit = 256,
  });

  /// How many unread rows one pass reads.
  ///
  /// The read is ordered so that rows with an unspent marker come first, which
  /// is what makes a backlog larger than this bound drain rather than stall:
  /// each pass spends the markers it read, that write is itself a signal, and
  /// the next pass takes the next batch. Because there is only ever one alert,
  /// those extra passes update the same notification instead of adding to a
  /// pile of them.
  final int limit;

  final MessageAlertStorePort store;
  final MessageAlertPresenterPort presenter;
  final VisibleConversationPort visible;
  final TimeSource clock;

  Future<MessageAlertOutcome> call({required bool alertPosted}) async {
    final pendingResult = await store.readPending(limit: limit);
    if (pendingResult case FailureResult()) {
      // Storage is unavailable. Nothing is posted, nothing is withdrawn, and no
      // marker is spent, so the next pass reaches exactly the same conclusion.
      return MessageAlertOutcome.idle;
    }
    final pending = (pendingResult as Success<List<PendingMessageAlert>>).value;
    final now = clock.now();
    final visibleConversationId = visible.conversationId;

    bool suppressedBy(PendingMessageAlert message) =>
        message.isMuted(now) || message.conversationId == visibleConversationId;

    final outstanding = pending
        .where((message) => !suppressedBy(message))
        .toList(growable: false);
    final fresh = outstanding
        .where((message) => !message.alerted)
        .toList(growable: false);
    // A deliberate suppression still spends the marker. Without that, leaving a
    // conversation or outliving a mute would alert for messages the user has
    // already been shown or has asked not to hear about.
    final suppressed = pending
        .where((message) => !message.alerted && suppressedBy(message))
        .map((message) => message.messageId)
        .toList(growable: false);

    if (fresh.isEmpty) {
      // Withdrawing needs certainty that nothing is left, and a full page is
      // evidence of the opposite: rows may exist past the bound. Refusing to
      // withdraw on a full page can only ever leave an alert standing a little
      // too long, never announce something that is not there.
      final hidden =
          outstanding.isEmpty && pending.length < limit && alertPosted;
      if (hidden) {
        await _hide();
      }
      await _markAlerted(suppressed);
      return MessageAlertOutcome(
        authorization: null,
        shown: false,
        hidden: hidden,
        body: null,
        markedAlerted: suppressed.length,
        requested: false,
      );
    }

    var platform = await _platformState();
    var requested = false;
    if (platform != null &&
        visible.isForeground &&
        platform.automaticPromptAllowed(
          everRequested: await _everRequested(),
        )) {
      // Point of use, and exactly once for the lifetime of the install: a
      // message is waiting that cannot be announced. Asking anywhere else would
      // be asking before there is anything to ask about, and asking twice is
      // how Android is told to stop showing the prompt for good.
      //
      // Foreground is required because the prompt belongs to an activity the
      // user is looking at. When the application is not, this pass simply does
      // not alert and spends no marker, and the next return to the foreground
      // is itself a signal that runs this again.
      requested = true;
      await store.recordPermissionRequested();
      platform = await _request();
    }
    final authorization =
        platform?.authorization ?? MessageAlertAuthorization.unavailable;

    if (authorization != MessageAlertAuthorization.granted) {
      // The fresh markers are deliberately *not* spent. Whatever could not be
      // announced stays eligible, so granting permission later announces the
      // backlog instead of losing it.
      await _markAlerted(suppressed);
      return MessageAlertOutcome(
        authorization: authorization,
        shown: false,
        hidden: false,
        body: null,
        markedAlerted: suppressed.length,
        requested: requested,
      );
    }

    final body = outstanding.length == 1
        ? MessageAlertBody.oneMessage
        : MessageAlertBody.manyMessages;
    if (!await _show(body)) {
      await _markAlerted(suppressed);
      return MessageAlertOutcome(
        authorization: authorization,
        shown: false,
        hidden: false,
        body: null,
        markedAlerted: suppressed.length,
        requested: requested,
      );
    }
    final spent = [...suppressed, ...fresh.map((message) => message.messageId)];
    await _markAlerted(spent);
    return MessageAlertOutcome(
      authorization: authorization,
      shown: true,
      hidden: false,
      body: body,
      markedAlerted: spent.length,
      requested: requested,
    );
  }

  Future<MessageAlertPlatformState?> _request() async {
    try {
      return await presenter.requestPermission();
    } on Object {
      return null;
    }
  }

  Future<MessageAlertPlatformState?> _platformState() async {
    try {
      return await presenter.platformState();
    } on Object {
      return null;
    }
  }

  Future<bool> _everRequested() async {
    final result = await store.readPermissionRequested();
    return switch (result) {
      Success(:final value) => value,
      // An unreadable marker is treated as "already asked", which withholds the
      // automatic prompt rather than risking a repeat of it.
      FailureResult() => true,
    };
  }

  Future<bool> _show(MessageAlertBody body) async {
    try {
      await presenter.show(body);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _hide() async {
    try {
      await presenter.hide();
    } on Object {
      // Withdrawing an alert that is already gone, or that the platform will
      // not talk about, is not a failure worth propagating.
    }
  }

  Future<void> _markAlerted(List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return;
    }
    await store.markAlerted(messageIds);
  }
}
