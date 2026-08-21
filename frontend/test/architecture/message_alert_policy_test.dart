import 'dart:io';

import 'package:communication_platform/features/notifications/infrastructure/platform_message_alert_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of the alert that only exist in the Android artifact.
///
/// The Kotlin here cannot be exercised by a host test, and no device is
/// available, so what is asserted is what the source may and may not contain.
/// These are the properties that would be silently wrong on a device rather
/// than loudly wrong in a test run: what the notification reveals, what the
/// tap carries, and which permissions the artifact asks for.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final activity = File(
    'android/app/src/main/kotlin/com/example/communication_platform/MainActivity.kt',
  ).readAsStringSync();

  test('the artifact asks for the notification permission and no more', () {
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    // The channel enables vibration, which the system performs on the app's
    // behalf. Declaring it is the unambiguous reading and costs a normal
    // permission with no prompt and no exposure.
    expect(manifest, contains('android.permission.VIBRATE'));
    // ADR-046 leaves the background layers unbuilt, and this piece may not
    // smuggle one in behind a notification.
    expect(manifest, isNot(contains('FOREGROUND_SERVICE')));
    expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
    expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
    expect(manifest, isNot(contains('USE_EXACT_ALARM')));
    expect(manifest, isNot(contains('RECEIVE_SMS')));
    expect(manifest, isNot(contains('<service')));
  });

  test('the alert is withheld from the lock screen by construction', () {
    // Not left to the system's own redaction: the visibility is declared, and
    // the public version is supplied, which is what Android 15 and above shows
    // during screen sharing instead of a contextless redaction.
    expect(activity, contains('VISIBILITY_PRIVATE'));
    expect(activity, contains('setPublicVersion'));
    // The arrival time is not shown; it is not needed to act on the alert and
    // it is one more thing a lock screen would tell someone holding the phone.
    expect(activity, contains('setShowWhen(false)'));
  });

  test('tapping the alert carries no destination and no identifier', () {
    // The launcher intent and nothing else. There is no extra to validate, no
    // deep link to forge, and no route that could bypass the guards the
    // application already has between an entry point and content.
    expect(activity, contains('getLaunchIntentForPackage'));
    expect(activity, contains('PendingIntent.FLAG_IMMUTABLE'));
    expect(
      activity,
      isNot(contains('putExtra(Intent.EXTRA_TEXT')),
      reason: 'nothing about a message may ride the tap intent',
    );
    expect(
      activity,
      isNot(contains('setShortcutId')),
      reason:
          'conversation shortcuts would publish a per-contact identifier into '
          'the launcher, which is the opposite of a sender-neutral alert',
    );
    expect(
      activity,
      isNot(contains('MessagingStyle')),
      reason: 'a messaging-style notification exists to show senders and text',
    );
  });

  test('the native side holds no policy about messages', () {
    // Everything the notification says is decided in Dart and arrives as a
    // reviewed, localized sentence, so the whole decision is covered by host
    // tests and one catalogue is translated.
    for (final forbidden in const [
      'unread',
      'conversation_id',
      'conversationId',
      'senderUserId',
      'messageId',
      'muted',
      'NotificationCompat.MessagingStyle',
    ]) {
      expect(
        activity,
        isNot(contains(forbidden)),
        reason: 'MainActivity must not learn anything about a message',
      );
    }
  });

  test('the channel is the only way in, and its identity is frozen', () {
    expect(
      activity,
      contains(PlatformMessageAlertPresenter.channelName),
      reason: 'the Dart and Kotlin halves must name the same channel',
    );
    // The channel id keys the user's own sound and importance settings.
    // Changing it discards them silently, so it is pinned here.
    expect(
      activity,
      contains('messageAlertNotificationChannelId = "messages"'),
    );
  });

  test('no notification dependency was added to reach the platform', () {
    // ADR-046 step 8 preferred app-owned Kotlin behind a port for this surface,
    // and `androidx.core` - already a declared dependency for FileProvider -
    // supplies every API the alert uses.
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    for (final package in const [
      'flutter_local_notifications',
      'awesome_notifications',
      'firebase',
      'workmanager',
      'flutter_foreground_task',
      'permission_handler',
    ]) {
      expect(pubspec, isNot(contains(package)));
    }
    expect(
      File('android/app/build.gradle.kts').readAsStringSync(),
      contains('androidx.core:core:'),
    );
  });

  test('the alert never reads a transport event', () {
    // The trigger is a committed durable row and nothing else. A dependency on
    // the socket, the gateway or the engine here would be the exact mistake
    // ADR-046 forbids: announcing something the server said rather than
    // something this device authenticated and committed.
    final reconciler = File(
      'lib/features/notifications/application/reconcile_message_alerts.dart',
    ).readAsStringSync();
    for (final forbidden in const [
      'Gateway',
      'WebSocket',
      'RealtimeSync',
      'DurableSyncEngine',
      'SyncRemotePort',
      'Envelope',
    ]) {
      expect(reconciler, isNot(contains(forbidden)));
    }
  });
}
