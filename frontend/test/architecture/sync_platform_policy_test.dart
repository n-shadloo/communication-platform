import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('messaging synchronization has no foreign push or foreground service', () {
    final pubspec = File('pubspec.yaml').readAsStringSync().toLowerCase();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final adapters = File(
      'lib/features/synchronization/infrastructure/sync_platform_adapters.dart',
    ).readAsStringSync();

    expect(pubspec, isNot(contains('firebase')));
    expect(pubspec, isNot(contains('firebase_messaging')));
    expect(manifest, isNot(contains('remoteMessaging')));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_DATA_SYNC')));
    expect(adapters, contains('AndroidPollingScheduler'));
    expect(adapters, contains('scheduleBestEffort'));
    expect(adapters, contains('headless callback'));
  });
}
