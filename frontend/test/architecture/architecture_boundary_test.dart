import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core and feature policy layers do not import outer-layer packages', () {
    const forbiddenImportFragments = [
      "package:flutter/",
      "package:dio/",
      "package:drift/",
      "package:drift_flutter/",
      "package:forui/",
      "package:flutter_chat_core/",
      "package:flutter_chat_ui/",
      "package:firebase_",
      "package:android_",
      "package:web/",
    ];
    final boundaryDirectories = [
      (
        directory: Directory('lib/core/domain'),
        allowedPackagePrefixes: ['package:communication_platform/core/domain/'],
      ),
      (
        directory: Directory('lib/core/protocol'),
        allowedPackagePrefixes: [
          'package:communication_platform/core/domain/',
          'package:communication_platform/core/protocol/',
          'package:communication_platform/core/result/',
        ],
      ),
      (
        directory: Directory('lib/core/application'),
        allowedPackagePrefixes: [
          'package:communication_platform/core/application/',
          'package:communication_platform/core/domain/',
          'package:communication_platform/core/protocol/',
          'package:communication_platform/core/result/',
        ],
      ),
    ];
    for (final feature in Directory('lib/features').listSync()) {
      if (feature is! Directory) {
        continue;
      }
      final featureName = feature.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      for (final layerName in const ['domain', 'application']) {
        final directory = Directory('${feature.path}/$layerName');
        if (!directory.existsSync()) {
          continue;
        }
        boundaryDirectories.add((
          directory: directory,
          allowedPackagePrefixes: [
            'package:communication_platform/core/',
            'package:communication_platform/features/$featureName/domain/',
            'package:communication_platform/features/$featureName/application/',
          ],
        ));
      }
    }
    final importPattern = RegExp(
      r"^\s*(?:import|export)\s+'([^']+)'",
      multiLine: true,
    );

    final violations = <String>[];
    for (final boundary in boundaryDirectories) {
      for (final entry in boundary.directory.listSync(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.dart')) {
          continue;
        }

        final source = entry.readAsStringSync();
        for (final fragment in forbiddenImportFragments) {
          if (source.contains(fragment)) {
            violations.add('${entry.path} imports $fragment');
          }
        }

        for (final match in importPattern.allMatches(source)) {
          final uri = match.group(1)!;
          final isAllowedDartLibrary = uri.startsWith('dart:');
          final isAllowedCoreImport = boundary.allowedPackagePrefixes.any(
            uri.startsWith,
          );
          if (!isAllowedDartLibrary && !isAllowedCoreImport) {
            violations.add('${entry.path} crosses the core boundary with $uri');
          }
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
