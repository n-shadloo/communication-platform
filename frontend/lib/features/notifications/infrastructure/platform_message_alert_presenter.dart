// ignore_for_file: prefer_initializing_formals

import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Localized alert text, resolved once by the composition root from the same
/// ARB catalogue every other user-facing string comes from.
///
/// The strings cross the channel rather than being read from Android string
/// resources so that one catalogue is reviewed, one catalogue is translated,
/// and the shade can never speak a different language from the application.
final class MessageAlertStrings {
  const MessageAlertStrings({
    required this.channelName,
    required this.channelDescription,
    required this.oneMessage,
    required this.manyMessages,
  });

  final String channelName;
  final String channelDescription;
  final String oneMessage;
  final String manyMessages;

  String titleFor(MessageAlertBody body) => switch (body) {
    MessageAlertBody.oneMessage => oneMessage,
    MessageAlertBody.manyMessages => manyMessages,
  };
}

/// The Android side of the alert, behind one method channel.
///
/// The channel carries no identifier of any kind: not a conversation, not a
/// sender, not a message. What crosses it is a reviewed localized sentence and
/// an instruction to show or withdraw it, so nothing this application knows
/// about who is talking to whom can reach the system notification service,
/// a notification listener, or a screen a bystander can see.
final class PlatformMessageAlertPresenter implements MessageAlertPresenterPort {
  const PlatformMessageAlertPresenter({
    required Future<MessageAlertStrings> Function() strings,
    MethodChannel channel = const MethodChannel(channelName),
  }) : _strings = strings,
       _channel = channel;

  static const channelName = 'communication_platform/message_alerts';

  /// Resolved per post rather than captured once, so a device language change
  /// reaches the next alert without the application being restarted.
  final Future<MessageAlertStrings> Function() _strings;
  final MethodChannel _channel;

  @override
  Future<MessageAlertPlatformState?> platformState() => _state('platformState');

  /// How long a prompt may stay unanswered before this gives up on it.
  ///
  /// The platform completes the call when the dialog is answered *or*
  /// dismissed, so this is not the normal path. It exists because a reply that
  /// never arrives would leave the reconciliation pass awaiting it forever, and
  /// a stalled pass is an alert path that has silently stopped.
  static const promptDeadline = Duration(minutes: 5);

  @override
  Future<MessageAlertPlatformState?> requestPermission() => _state(
    'requestPermission',
  ).timeout(promptDeadline, onTimeout: () => null);

  /// Posting is the one call that must fail loudly.
  ///
  /// Everything else on this port answers a question, and "no answer" is a
  /// usable answer. A post that quietly did nothing would be indistinguishable
  /// from a post that worked, and the reconciler would spend the durable marker
  /// on an alert the user never saw - which is a message they are never told
  /// about. So this rethrows, and the caller treats a throw as "not shown".
  @override
  Future<void> show(MessageAlertBody body) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('No message alert implementation on this target.');
    }
    final strings = await _strings();
    await _channel.invokeMethod<void>('show', {
      'title': strings.titleFor(body),
      'channelName': strings.channelName,
      'channelDescription': strings.channelDescription,
    });
  }

  @override
  Future<void> hide() => _invoke<void>('hide', const <String, Object?>{});

  @override
  Future<void> openSystemSettings() =>
      _invoke<void>('openSystemSettings', const <String, Object?>{});

  Future<MessageAlertPlatformState?> _state(String method) async {
    final reply = await _invoke<Map<Object?, Object?>>(
      method,
      const <String, Object?>{},
    );
    if (reply == null) {
      return null;
    }
    final enabled = reply['enabled'];
    final runtimePermission = reply['runtimePermission'];
    final rationale = reply['rationale'];
    if (enabled is! bool || runtimePermission is! bool || rationale is! bool) {
      // A reply this code does not understand is treated as no implementation
      // at all rather than as a permissive default.
      return null;
    }
    return MessageAlertPlatformState(
      enabled: enabled,
      runtimePermission: runtimePermission,
      rationale: rationale,
    );
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    // The check is on the target platform rather than on `dart:io`, because
    // this file must stay importable by a future Web build and because a test
    // has to be able to drive the Android path without an Android device.
    if (defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

/// The presenter for a build with no platform implementation behind it.
///
/// It reports [MessageAlertAuthorization.unavailable] through a null state and
/// posts nothing, so a host test, a future Web target, or a desktop build says
/// plainly that it cannot alert instead of appearing to.
final class UnavailableMessageAlertPresenter
    implements MessageAlertPresenterPort {
  const UnavailableMessageAlertPresenter();

  @override
  Future<MessageAlertPlatformState?> platformState() async => null;

  @override
  Future<MessageAlertPlatformState?> requestPermission() async => null;

  /// Reachable only through a caller that ignored the null platform state, so
  /// it refuses rather than returning as though it had posted something.
  @override
  Future<void> show(MessageAlertBody body) async =>
      throw StateError('No message alert implementation is composed.');

  @override
  Future<void> hide() async {}

  @override
  Future<void> openSystemSettings() async {}
}
