import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release baseline disables cleartext and user-CA trust', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final baseline = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(baseline, contains('cleartextTrafficPermitted="false"'));
    expect(baseline, isNot(contains('<certificates src="user"')));
  });

  test('Android provisioning template requires a private CA and two pins', () {
    final template = File(
      'android/provisioning/network_security_config.xml.template',
    ).readAsStringSync();

    expect(template, contains('@raw/provisioned_private_ca'));
    expect(template, contains('@@SERVER_HOST@@'));
    expect(template, contains('@@PRIMARY_SPKI_SHA256@@'));
    expect(template, contains('@@BACKUP_SPKI_SHA256@@'));
    expect(
      RegExp(r'<pin digest="SHA-256">').allMatches(template),
      hasLength(2),
    );
    expect(template, isNot(contains('src="user"')));
  });

  test('Web bootstrap declares only same-artifact runtime resources', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('src="flutter_bootstrap.js"'));
    expect(index, contains('href="manifest.json"'));
    expect(index, isNot(contains('src="http')));
    expect(index, isNot(contains('href="http')));
  });
}
