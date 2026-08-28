import 'dart:convert';
import 'dart:io';

import 'package:communication_platform/features/synchronization/infrastructure/platform_sustained_delivery_port.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of ADR-051 that only exist in the Android artifact.
///
/// None of this can be exercised by a host test and no device is available, so
/// what is asserted is what the source may and may not contain. These are the
/// properties that would be silently wrong on a device rather than loudly wrong
/// in a test run: whether what the artifact declares to the platform is true,
/// what the permanent entry reveals, what starts the service and what could
/// never start it, and whether a future change could quietly make any of that
/// stop being the case.
void main() {
  const kotlinRoot =
      'android/app/src/main/kotlin/com/example/communication_platform';
  final manifestSource = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  // Declarations only. The manifest explains at length why the other service
  // types were rejected, and an assertion that tripped over its own reasoning
  // would push that reasoning out of the file where it belongs.
  final manifest = manifestSource.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  final sustainedSource = File(
    '$kotlinRoot/SustainedDelivery.kt',
  ).readAsStringSync();
  // Code only, for the same reason: this file records at length why the other
  // service types and the other notification importances were rejected, and an
  // assertion that tripped over its own reasoning would push that reasoning out
  // of the file where it belongs.
  final sustained = sustainedSource
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');
  final delivery = File('$kotlinRoot/BackgroundDelivery.kt').readAsStringSync();

  group('what the artifact declares, and whether it is true', () {
    test('the service is `specialUse`, and says why in the manifest', () {
      expect(manifest, contains('android:name=".SustainedDeliveryService"'));
      expect(manifest, contains('android:foregroundServiceType="specialUse"'));
      expect(manifest, contains('android:exported="false"'));
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE'),
        reason:
            'an app targeting API 34+ that starts a typed foreground service '
            'without the matching permission is thrown a SecurityException',
      );
      final subtype = RegExp(
        r'PROPERTY_SPECIAL_USE_FGS_SUBTYPE"\s*\n\s*android:value="([^"]*)"',
      ).firstMatch(manifest);
      expect(subtype, isNotNull, reason: 'the case must be stated');
      final justification = subtype!.group(1)!;
      // The declaration has to be true, and these are the three claims in it
      // that a future change could most easily falsify: what the service is
      // for, why no push transport is used instead, and that it is opt-in.
      for (final claim in const [
        'cached state',
        'self-hosted',
        'push',
        'user explicitly turns the capability on',
      ]) {
        expect(justification, contains(claim));
      }
      expect(
        justification.length,
        greaterThan(200),
        reason:
            'the type exists for cases the other types do not cover, and the '
            'reviewer of such a declaration is entitled to the reasoning',
      );
    });

    test('the service is never given a type it would not deserve', () {
      // ADR-046 rejected these three and ADR-051 re-derived the rejection.
      // `dataSync` is capped at six hours per twenty-four and cannot start from
      // a boot receiver at targetSdk 35+; `remoteMessaging` describes carrying
      // a user's text messages between their own devices; `systemExempted` is
      // gated on device-owner, VPN, emergency or exact-alarm roles this
      // application does not have and must not acquire.
      for (final forbidden in const [
        'dataSync',
        'remoteMessaging',
        'systemExempted',
        'shortService',
        'mediaProcessing',
        'FOREGROUND_SERVICE_TYPE_DATA_SYNC',
        'FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING',
        'FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED',
      ]) {
        expect(manifest, isNot(contains(forbidden)));
        expect(sustained, isNot(contains(forbidden)));
      }
      expect(
        sustained,
        contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE'),
      );
    });

    test('the exemption is asked for, never assumed, and never faked', () {
      expect(
        manifest,
        contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
      );
      expect(
        sustained,
        contains('Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
        reason:
            'the documented intent, which Android sanctions for a chat app '
            'that cannot reach a push transport',
      );
      expect(
        sustained,
        contains('isIgnoringBatteryOptimizations'),
        reason:
            'the dialog reports refusal and dismissal identically, so the only '
            'trustworthy answer is what the platform says afterwards',
      );
      // The answer is never inferred from the dialog returning.
      expect(sustained, isNot(contains('onActivityResult')));
      expect(sustained, isNot(contains('startActivityForResult')));
    });

    test('everything still runs in one process', () {
      // A third delivery owner arrived with this piece, and the whole
      // single-owner argument is that every owner lives in one process with one
      // Dart VM. A second process would put a second VM beside it and the
      // in-process arbitration would arbitrate nothing (ADR-050).
      expect(manifest, isNot(contains('android:process')));
    });
  });

  group('what the permanent entry reveals', () {
    test('it is silent, low, and withheld from a locked screen', () {
      expect(sustained, contains('IMPORTANCE_LOW'));
      expect(
        sustained,
        isNot(contains('IMPORTANCE_MIN')),
        reason:
            'the platform documents MIN as wrong for a foreground service and '
            'answers it by showing a higher-priority notice instead',
      );
      expect(
        sustained,
        contains('VISIBILITY_SECRET'),
        reason:
            'no part of it may appear on a secure lock screen or while the '
            'screen is being shared',
      );
      expect(sustained, contains('setSilent(true)'));
      expect(sustained, contains('setVibrationEnabled(false)'));
      expect(
        sustained,
        contains('setShowWhen(false)'),
        reason:
            'the moment this was armed is one more thing a bystander would '
            'otherwise learn',
      );
      expect(sustained, contains('setShowBadge(false)'));
    });

    test('it carries no destination, no identifier, and no message', () {
      expect(sustained, contains('getLaunchIntentForPackage'));
      expect(sustained, contains('PendingIntent.FLAG_IMMUTABLE'));
      for (final forbidden in const [
        'MessagingStyle',
        'setShortcutId',
        'EXTRA_TEXT',
        'conversationId',
        'messageId',
        'senderUserId',
        'unread',
      ]) {
        expect(sustained, isNot(contains(forbidden)));
      }
    });

    test('its text is reviewed and localized, never assembled natively', () {
      // The three strings cross the channel with the start, so one catalogue is
      // reviewed and one catalogue is translated. A service handed no text
      // starts nothing rather than inventing a sentence.
      expect(sustained, contains('EXTRA_TITLE'));
      expect(sustained, contains('title.isEmpty()'));
      expect(sustained, contains('return null'));
      expect(
        sustained,
        isNot(contains('R.string')),
        reason: 'Android string resources are a second, unreviewed catalogue',
      );
      expect(sustained, contains(PlatformSustainedDeliveryPort.channelName));
    });

    test('a start is answered when it lands, not when it is asked for', () {
      // Starting and stopping a service are asynchronous: `onStartCommand` and
      // `onDestroy` are posted to the same looper the call that asked for them
      // runs on, so they cannot have happened by the time it returns. Answering
      // immediately would report "not running" for every start, and the enable
      // flow would read a service that is about to appear as one the platform
      // refused - roll the choice back, and tell the user it failed. Nothing in
      // a host test can catch that, so the shape is pinned here.
      expect(sustained, contains('transitionWaiters'));
      expect(sustained, contains('fun awaitTransition('));
      expect(
        sustained,
        contains('settleTransitions(context)'),
        reason: 'the answer is released by the transition itself',
      );
      expect(
        sustained,
        contains('TRANSITION_TIMEOUT_MS'),
        reason:
            'and by a bound, so a transition that never lands still answers',
      );
      // And no path answers before the thing it is answering about: the two
      // branches that change the service hand their result to `awaitTransition`
      // and never complete it themselves.
      final handler = sustained.substring(
        sustained.indexOf('"start" ->'),
        sustained.indexOf('"finished" ->'),
      );
      expect('awaitTransition('.allMatches(handler), hasLength(2));
      expect(
        handler,
        isNot(contains('result.success')),
        reason: 'a start or a stop is answered by the transition landing',
      );
    });

    test('nothing about the run is logged', () {
      expect(sustained, isNot(contains('Log.')));
      expect(sustained, isNot(contains('println')));
    });
  });

  group('nothing runs until it is chosen', () {
    test(
      'the service is started only by this application, never by the platform',
      () {
        // No boot receiver, no launcher, no exported entry point. The only thing
        // that starts this is a Dart isolate that has already read the durable
        // choice out of the encrypted database, so a build nobody enabled it in
        // never reaches any of it.
        expect(_declaredReceivers(manifest), isEmpty);
        expect(
          manifest,
          isNot(contains('android.intent.action.BOOT_COMPLETED')),
          reason:
              'the RECEIVE_BOOT_COMPLETED permission the deferred catch-up needs '
              'for setPersisted is not a receiver, and this piece declares none',
        );
        expect(sustained, isNot(contains('BroadcastReceiver')));
        expect(sustained, isNot(contains('BOOT_COMPLETED')));
        expect(
          sustained,
          contains('ContextCompat.startForegroundService'),
          reason: 'the one start path',
        );
        expect('startForegroundService'.allMatches(sustained), hasLength(1));
      },
    );

    test('a restarted service re-reads the choice before it does anything', () {
      // START_REDELIVER_INTENT rather than START_STICKY, because a sticky
      // restart arrives with a null intent and this service may display only
      // text that crossed the channel with the start.
      expect(sustained, contains('START_REDELIVER_INTENT'));
      expect(sustained, isNot(contains('START_STICKY')));
      final run = File(
        'lib/app/dependencies/sustained_delivery_run.dart',
      ).readAsStringSync();
      final readsChoice = run.indexOf('DriftSustainedDeliveryStore(database)');
      final restores = run.indexOf('useCases.restore()');
      expect(readsChoice, greaterThan(-1));
      expect(
        readsChoice,
        lessThan(restores),
        reason:
            'a restart may not resurrect a capability the user turned off, and '
            'may not touch a token before it knows it is allowed to run',
      );
      expect(run, contains('SustainedRunOutcome.notChosen'));
    });

    test('nothing durable is written anywhere but the encrypted database', () {
      for (final forbidden in const [
        'SharedPreferences',
        'getSharedPreferences',
        'FileOutputStream',
        'openFileOutput',
        'ContentProvider',
      ]) {
        expect(
          sustained,
          isNot(contains(forbidden)),
          reason:
              'the choice is a fact about its owner and belongs behind the '
              'same key as every other durable fact this application holds',
        );
      }
    });
  });

  group('what the third delivery owner can reach', () {
    final run = File(
      'lib/app/dependencies/sustained_delivery_run.dart',
    ).readAsStringSync();

    test('it inherits the composition root rather than rebuilding one', () {
      // The dangerous failure is not a crash, it is a quieter posture: the
      // public root store instead of the provisioned authority, a second token
      // coordinator, a crypto core built without the compiled environment's
      // permit. One constructor removes the possibility.
      expect(run, contains('ApplicationRuntime.create('));
      for (final forbidden in const [
        'TransportSecurity.platformDefault',
        'NetworkingFoundation.create',
        'TokenCoordinator(',
        'DioRestClient(',
      ]) {
        expect(
          run,
          isNot(contains(forbidden)),
          reason: 'a background entry point composes no transport of its own',
        );
      }
    });

    test('it is one owner among three, arbitrated on one thread', () {
      // ADR-050 established that exactly one part of this application drives
      // delivery, and named this piece as the third owner whose arrival would
      // require the arbitration to be re-derived. This is that arbitration.
      expect(
        delivery,
        contains('SustainedDelivery.requestStandDown()'),
        reason: 'attaching a foreground engine displaces the sustained run',
      );
      expect(
        delivery,
        contains('SustainedDelivery.isRunning()'),
        reason:
            'the foreground waits for it, exactly as it waits for a catch-up: '
            'both are root isolates with a token coordinator of their own',
      );
      expect(
        delivery,
        contains('SustainedDelivery.channelOfRun()'),
        reason:
            'a deferred tick goes to the owner that already exists rather than '
            'starting a second engine beside it',
      );
      expect(delivery, contains('fun beginSustainedIfIdle('));
      expect(run, contains('handshake.displaced'));
      expect(run, contains('standDown: handshake'));
      // Asked, never killed. Displacing a run invokes one channel method and
      // nothing else; the engine is torn down only when the Dart side reports
      // that it has finished, or when the platform has already taken the
      // decision away by stopping the service.
      final standDown = sustained.substring(
        sustained.indexOf('internal fun requestStandDown()'),
        sustained.indexOf('private class SustainedRun('),
      );
      expect(standDown, contains('run?.requestStandDown()'));
      for (final forbidden in const ['destroy', 'abandon', 'stopSelf']) {
        expect(
          standDown,
          isNot(contains(forbidden)),
          reason:
              'abandoning a transaction or a call into the shared native '
              'cryptographic core part-way is worse than waiting',
        );
      }
    });

    test('it holds a connection, which is the whole of what it adds', () {
      expect(run, contains('SyncLifecycleSupervisor'));
      expect(run, contains('AlwaysHoldsInBackground'));
      expect(
        run,
        contains('BackgroundedExecution'),
        reason:
            'the application really is backgrounded; what permits the socket '
            'is the service, not a foreground state it does not have',
      );
      expect(
        run,
        isNot(contains('polling.schedule')),
        reason:
            'the periodic job is armed once by whoever owns the signed-in '
            'session; re-registering it restarts its window',
      );
      // And it ends for one of two reasons that are not the same reason. Being
      // displaced hands delivery to a foreground the user is looking at, and
      // the service goes on keeping this process alive for when they leave
      // again; a session that ended has nothing left to deliver to, and a
      // permanent entry for an account nobody is signed into announces the
      // account rather than a message.
      expect(run, contains('SustainedRunOutcome.noSession'));
      expect(run, contains('terminations.cancel()'));
      expect(
        run,
        contains('sustainedRunStopsService'),
        reason: 'which of the two happened is what decides whether it stops',
      );
    });
  });

  group('what the user is told', () {
    test('every string exists in both catalogues and neither is empty', () {
      final english =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      final persian =
          jsonDecode(File('lib/l10n/app_fa.arb').readAsStringSync())
              as Map<String, dynamic>;
      const keys = [
        'sustainedNotificationTitle',
        'sustainedChannelName',
        'sustainedChannelDescription',
        'settingsSustainedTitle',
        'settingsSustainedOff',
        'settingsSustainedHolding',
        'settingsSustainedAlertsWithheld',
        'settingsSustainedExemptionWithdrawn',
        'settingsSustainedStopped',
        'settingsSustainedUnavailable',
        'sustainedTitle',
        'sustainedWhatItDoes',
        'sustainedWhatItCosts',
        'sustainedWhatItCannotPromise',
        'sustainedNeedsTitle',
        'sustainedNeedsAlerts',
        'sustainedNeedsExemption',
        'sustainedNeedsVendor',
        'sustainedVendorAction',
        'sustainedTurnOn',
        'sustainedTurnOff',
        'sustainedStatusOff',
        'sustainedStatusHolding',
        'sustainedStatusAlertsWithheld',
        'sustainedStatusExemptionWithdrawn',
        'sustainedStatusStopped',
        'sustainedStatusUnavailable',
        'sustainedRefusedAlerts',
        'sustainedRefusedExemption',
        'sustainedRefusedPlatform',
        'sustainedRefusedNotRecorded',
        'sustainedRefusedUnavailable',
      ];
      for (final key in keys) {
        expect(english[key], isA<String>(), reason: 'missing English $key');
        expect((english[key] as String).trim(), isNotEmpty);
        expect(persian[key], isA<String>(), reason: 'missing Persian $key');
        expect((persian[key] as String).trim(), isNotEmpty);
        expect(
          persian[key],
          isNot(english[key]),
          reason: 'untranslated Persian $key',
        );
      }
    });

    test('the explanation states the cost and refuses to promise', () {
      final english =
          jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
              as Map<String, dynamic>;
      // The three sentences that make this honest rather than a feature pitch.
      expect(english['sustainedWhatItCosts'], contains('more battery'));
      expect(
        english['sustainedWhatItCosts'],
        contains('permanent notice'),
        reason: 'the exposure is stated before the choice, not after it',
      );
      expect(
        english['sustainedWhatItCannotPromise'],
        contains('cannot promise'),
      );
      expect(
        english['sustainedNeedsVendor'],
        contains('cannot check'),
        reason:
            'the manufacturer step is the user’s to perform and this '
            'application can never confirm it',
      );
      // And nothing anywhere in this surface may claim it will work.
      for (final key in const [
        'sustainedWhatItDoes',
        'sustainedWhatItCosts',
        'sustainedWhatItCannotPromise',
        'sustainedStatusHolding',
        'settingsSustainedHolding',
      ]) {
        final text = (english[key]! as String).toLowerCase();
        for (final forbidden in const [
          'guarantee',
          'always',
          'never miss',
          'reliable',
        ]) {
          expect(
            text,
            isNot(contains(forbidden)),
            reason: '$key must not promise what the platform does not',
          );
        }
      }
    });
  });
}

/// Every `<receiver>` element in the manifest that actually declares a
/// component, as opposed to refusing one contributed from outside.
///
/// ADR-054 added the only `<receiver>` element this manifest has ever carried:
/// a `tools:node="remove"` directive that deletes the exported receiver
/// `androidx.profileinstaller` merges in. That is the opposite of declaring an
/// entry point, so the invariant is stated over declarations rather than over
/// the literal text.
Iterable<String> _declaredReceivers(String manifest) =>
    RegExp(r'<receiver[^>]*>', dotAll: true)
        .allMatches(manifest)
        .map((match) => match.group(0)!)
        .where((element) => !element.contains('tools:node="remove"'));
