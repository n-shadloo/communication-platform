import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the application exposes app, core, shared, and feature boundaries', () {
    for (final path in const [
      'lib/app',
      'lib/core',
      'lib/shared',
      'lib/features',
    ]) {
      expect(Directory(path).existsSync(), isTrue, reason: '$path is required');
    }

    expect(
      File(
        'lib/features/bootstrap/presentation/bootstrap_page.dart',
      ).existsSync(),
      isTrue,
      reason: 'the existing bootstrap capability must be visible as a feature',
    );
    expect(
      Directory('lib/config').existsSync(),
      isFalse,
      reason: 'application configuration belongs under lib/app',
    );
  });

  test('feature modules use only recognized clean-architecture layers', () {
    const allowedLayers = {
      'domain',
      'application',
      'infrastructure',
      'presentation',
    };
    final violations = <String>[];

    for (final feature in Directory('lib/features').listSync()) {
      if (feature is! Directory) {
        continue;
      }
      for (final entry in feature.listSync()) {
        if (entry is Directory) {
          final layerName = entry.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last;
          if (!allowedLayers.contains(layerName)) {
            violations.add(entry.path);
          }
        } else if (entry is File && entry.path.endsWith('.dart')) {
          violations.add(entry.path);
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
