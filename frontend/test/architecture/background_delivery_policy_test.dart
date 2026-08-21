import 'dart:io';

import 'package:communication_platform/features/synchronization/infrastructure/platform_deferred_delivery_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parts of ADR-049 that only exist in the Android artifact.
///
/// None of this can be exercised by a host test and no device is available, so
/// what is asserted is what the source may and may not contain. These are the
/// properties that would be silently wrong on a device rather than loudly wrong
/// in a test run: what the artifact asks the platform for, what it declares to
/// it, what the second entry point can reach, and what it may never quietly
/// stop inheriting.
void main() {
  const kotlinRoot =
      'android/app/src/main/kotlin/com/example/communication_platform';
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final delivery = File('$kotlinRoot/BackgroundDelivery.kt').readAsStringSync();

  group('what the artifact declares to the platform', () {
    test('the only service is a job service, bound and unexported', () {
      // A foreground service would be the other way to get timeliness, and it
      // needs an exemption the user has to grant and a permanent entry in the
      // shade. This piece is defined by needing neither.
      expect('<service'.allMatches(manifest), hasLength(1));
      expect(manifest, contains('android:name=".DeferredDeliveryJobService"'));
      expect(
        manifest,
        contains('android:permission="android.permission.BIND_JOB_SERVICE"'),
        reason:
            'without it the system ignores the service, and with it nothing '
            'but the job scheduler can start it',
      );
      expect(manifest, contains('android:exported="false"'));
      expect(manifest, isNot(contains('foregroundServiceType')));
      expect(
        manifest,
        isNot(
          contains('android:permission="android.permission.FOREGROUND_SERVICE'),
        ),
      );
    });

    test('everything runs in one process, which is what makes one owner', () {
      // The whole single-owner argument is that a job runs in this
      // application's own process and a Flutter process has one Dart VM. A
      // second process would put a second Dart VM beside it and the in-process
      // arbitration would arbitrate nothing.
      expect(manifest, isNot(contains('android:process')));
    });

    test(
      'no permission is asked for that a user could refuse or a vendor gate',
      () {
        expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
        for (final forbidden in const [
          'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          'SCHEDULE_EXACT_ALARM',
          'USE_EXACT_ALARM',
          'FOREGROUND_SERVICE',
          'RECEIVE_SMS',
          'WAKE_LOCK',
        ]) {
          expect(
            manifest,
            isNot(contains(forbidden)),
            reason:
                'this piece must work with nothing granted, configured or '
                'changed by the user',
          );
        }
      },
    );
  });

  group('what the artifact asks the platform for', () {
    test('a periodic job at the platform floor, with a network constraint', () {
      expect(delivery, contains('setPeriodic('));
      expect(
        delivery,
        contains('JobInfo.getMinPeriodMillis()'),
        reason:
            'the floor is read from the platform rather than repeated as a '
            'number that could drift away from it',
      );
      expect(delivery, contains('JobInfo.NETWORK_TYPE_ANY'));
      expect(
        delivery,
        contains('setPersisted(true)'),
        reason: 'a restart must not silently end background delivery',
      );
    });

    test('it never buys timeliness with something else', () {
      for (final forbidden in const [
        'AlarmManager',
        'setExactAndAllowWhileIdle',
        'setAndAllowWhileIdle',
        'startForeground',
        'ServiceInfo.FOREGROUND_SERVICE_TYPE',
        'isIgnoringBatteryOptimizations',
        'FirebaseMessaging',
      ]) {
        expect(delivery, isNot(contains(forbidden)));
      }
    });

    test('it wakes to drain its own mailbox, never to probe a public host', () {
      // ADR-013: no foreign runtime call of any kind, and never a connectivity
      // probe against something outside the provisioned deployment.
      for (final forbidden in const ['http://', 'https://', 'InetAddress']) {
        expect(delivery, isNot(contains(forbidden)));
      }
    });

    test('nothing about the run is logged', () {
      expect(delivery, isNot(contains('Log.')));
      expect(delivery, isNot(contains('println')));
    });

    test('no dependency was added to reach the platform', () {
      // `JobScheduler` is in the framework at minSdk 24. `androidx.work` would
      // add its own database, its own service and its own boot receiver to the
      // merged manifest of a security-reviewed artifact, to schedule one job.
      final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
      final gradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync().toLowerCase();
      for (final package in const ['workmanager', 'firebase', 'unifiedpush']) {
        expect(pubspec, isNot(contains(package)));
      }
      expect(gradle, isNot(contains('androidx.work')));
    });
  });

  group('what the second entry point can reach', () {
    final headless = File(
      'lib/app/dependencies/deferred_delivery_catch_up.dart',
    ).readAsStringSync();

    test('it inherits the composition root rather than rebuilding one', () {
      // The dangerous failure is not a crash, it is a quieter posture: the
      // public root store instead of the provisioned authority, a second token
      // coordinator, a crypto core built without the compiled environment's
      // permit. One constructor removes the possibility.
      expect(headless, contains('ApplicationRuntime.create('));
      for (final forbidden in const [
        'TransportSecurity.platformDefault',
        'NetworkingFoundation.create',
        'TokenCoordinator(',
        'DioRestClient(',
      ]) {
        expect(
          headless,
          isNot(contains(forbidden)),
          reason: 'a background entry point composes no transport of its own',
        );
      }
    });

    test('it holds nothing: one drain, no socket, no supervisor', () {
      for (final forbidden in const [
        'SyncLifecycleSupervisor',
        'WebSocketGateway',
        'GatewayRealtimeSyncAdapter',
        'realtimeGateway',
      ]) {
        expect(
          headless,
          isNot(contains(forbidden)),
          reason:
              'a bounded wake-up cannot hold a connection: a cached process is '
              'frozen and the system terminates its TCP sockets',
        );
      }
    });

    test('the headless engine is given the channels it cannot do without', () {
      // A headless engine reaches only the plugins Flutter registers
      // automatically. Without these two attached to it, the run could not
      // unwrap the database key at all, and could not say anything to the user
      // about what it drained.
      expect(delivery, contains('ProtectedStorageChannel(applicationContext)'));
      expect(delivery, contains('MessageAlertChannel(applicationContext)'));
      expect(delivery, contains(PlatformDeferredDeliveryScheduler.channelName));
    });
  });

  group('which build a background run believes it is', () {
    test('the compiled entry point fixes the environment, not the platform', () {
      // ADR-036 and ADR-044 hold that the environment decides the provisioned
      // server, the trust anchor and the closed-beta group permit, and that it
      // must be fixed by the entry point rather than selectable at runtime. The
      // platform picks a name; which `AppEnvironment` that name resolves to is
      // decided by which file was compiled.
      const flavors = {
        'lib/main.dart': 'AppEnvironment.development',
        'lib/main_development.dart': 'AppEnvironment.development',
        'lib/main_beta.dart': 'AppEnvironment.beta',
        'lib/main_production.dart': 'AppEnvironment.production',
      };
      flavors.forEach((path, environment) {
        final source = File(path).readAsStringSync();
        expect(source, contains("@pragma('vm:entry-point')"), reason: path);
        expect(
          source,
          contains('runDeferredDeliveryEntryPoint($environment)'),
          reason: path,
        );
      });
      expect(delivery, contains('ENTRYPOINT = "backgroundDelivery"'));
      expect(
        delivery,
        isNot(contains('dartEntrypointArgs')),
        reason:
            'nothing about which build this is may cross the boundary at '
            'runtime',
      );
    });
  });
}
