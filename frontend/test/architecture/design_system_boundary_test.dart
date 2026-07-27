import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature presentation does not import Forui or package icon APIs', () {
    final violations = <String>[];
    for (final entry in Directory('lib/features').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) {
        continue;
      }
      final source = entry.readAsStringSync();
      if (source.contains("package:forui/") ||
          source.contains('FLucideIcons')) {
        violations.add(entry.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('FLucideIcons are referenced only by the semantic AppIcons mapping', () {
    final references = <String>[];
    for (final entry in Directory('lib').listSync(recursive: true)) {
      if (entry is! File || !entry.path.endsWith('.dart')) {
        continue;
      }
      if (entry.readAsStringSync().contains('FLucideIcons')) {
        references.add(entry.path.replaceAll('\\', '/'));
      }
    }
    expect(references, ['lib/app/design_system/app_icons.dart']);
  });
}
