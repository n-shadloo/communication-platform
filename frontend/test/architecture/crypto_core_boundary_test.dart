import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart exposes only the narrow version-1 foundation boundary', () {
    final port = File(
      'lib/core/application/ports/crypto_core_port.dart',
    ).readAsStringSync();
    final bindings = File(
      'lib/shared/infrastructure/crypto/native/crypto_core_ffi.dart',
    ).readAsStringSync();

    expect(port, contains('capabilities()'));
    expect(port, contains('selfTest()'));
    expect(port, contains('close()'));
    for (final forbidden in const [
      'Uint8List',
      'dart:ffi',
      'encrypt(',
      'decrypt(',
      'sign(',
      'deriveKey(',
      'randomBytes(',
    ]) {
      expect(port, isNot(contains(forbidden)));
    }

    for (final symbol in const [
      'cp_crypto_v1_abi_version',
      'cp_crypto_v1_capabilities',
      'cp_crypto_v1_self_test',
    ]) {
      expect(bindings, contains("'$symbol'"));
    }
    expect(bindings, isNot(contains('last_error')));
    expect(bindings, isNot(contains('error_message')));
  });

  test('Web is explicitly unsupported and Dart contains no crypto package', () {
    final webAdapter = File(
      'lib/shared/infrastructure/crypto/platform_crypto_core_web.dart',
    ).readAsStringSync();
    expect(webAdapter, contains('UnsupportedCryptoCore'));

    final violations = <String>[];
    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) {
        continue;
      }
      final source = entry.readAsStringSync();
      for (final forbidden in const [
        'package:cryptography/',
        'package:pinenacl/',
        'package:pointycastle/',
      ]) {
        if (source.contains(forbidden)) {
          violations.add('${entry.path}: $forbidden');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('native boundary never logs or stringifies caught exceptions', () {
    final nativeDirectory = Directory(
      'lib/shared/infrastructure/crypto/native',
    );
    final violations = <String>[];
    for (final entry in nativeDirectory.listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) {
        continue;
      }
      final source = entry.readAsStringSync();
      for (final forbidden in const [
        'print(',
        'developer.log',
        'exception.toString()',
        'error.toString()',
      ]) {
        if (source.contains(forbidden)) {
          violations.add('${entry.path}: $forbidden');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
