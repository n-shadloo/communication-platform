import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android storage uses Keystore wrapping, SQLCipher, and no backup', () {
    final activity = File(
      'android/app/src/main/kotlin/com/example/communication_platform/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(activity, contains('AndroidKeyStore'));
    expect(activity, contains('AES/GCM/NoPadding'));
    expect(activity, contains('setIsStrongBoxBacked(true)'));
    expect(activity, contains('noBackupFilesDir'));
    expect(activity, isNot(contains('Log.')));
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(pubspec, contains('source: sqlcipher'));
  });

  test(
    'Web wrapping key is non-extractable and authenticated in IndexedDB',
    () {
      final bridge = File('web/protected_storage.js').readAsStringSync();
      final index = File('web/index.html').readAsStringSync();

      expect(index, contains('src="protected_storage.js"'));
      expect(bridge, contains('indexedDB.open'));
      expect(bridge, contains("{ name: 'AES-GCM', length: 256 }"));
      expect(bridge, contains('false,'));
      expect(bridge, contains('additionalData: aad'));
      expect(bridge, contains('wrappingKey.extractable !== false'));
      expect(bridge, isNot(contains('localStorage')));
      expect(bridge, isNot(contains('messageBody')));
      expect(bridge, isNot(contains('fileName')));
      expect(bridge, isNot(contains('profileName')));
      expect(bridge, isNot(contains('roomName')));
    },
  );

  test('platform APIs do not leak into domain or application layers', () {
    final violations = <String>[];
    for (final root in [
      Directory('lib/features/local_storage/domain'),
      Directory('lib/features/local_storage/application'),
    ]) {
      for (final entry in root.listSync(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.dart')) continue;
        final source = entry.readAsStringSync();
        for (final forbidden in const [
          'MethodChannel',
          'dart:js_interop',
          'package:drift/',
          'AndroidKeyStore',
          'indexedDB',
        ]) {
          if (source.contains(forbidden)) {
            violations.add('${entry.path}: $forbidden');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
