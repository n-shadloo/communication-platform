import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Vazirmatn')..addFont(
          rootBundle.load('assets/fonts/vazirmatn/Vazirmatn-Variable.ttf'),
        ))
        .load();
    await (FontLoader('packages/forui_assets/ForuiLucideIcons')
          ..addFont(rootBundle.load('packages/forui_assets/assets/lucide.ttf')))
        .load();
  });

  testWidgets('narrow English light shell', (tester) async {
    await _pumpGolden(tester, size: const Size(360, 800));
    await expectLater(
      find.byKey(const ValueKey('app-shell-golden')),
      matchesGoldenFile('goldens/shell_narrow_ltr.png'),
    );
  });

  testWidgets('medium Persian RTL shell', (tester) async {
    await _pumpGolden(
      tester,
      size: const Size(800, 900),
      locale: const Locale('fa'),
    );
    await expectLater(
      find.byKey(const ValueKey('app-shell-golden')),
      matchesGoldenFile('goldens/shell_medium_rtl.png'),
    );
  });

  testWidgets('wide English dark shell', (tester) async {
    await _pumpGolden(
      tester,
      size: const Size(1440, 900),
      themeMode: ThemeMode.dark,
    );
    await expectLater(
      find.byKey(const ValueKey('app-shell-golden')),
      matchesGoldenFile('goldens/shell_wide_dark.png'),
    );
  });

  testWidgets('narrow shell at 200 percent text scale', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpGolden(tester, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('app-shell-golden')),
      matchesGoldenFile('goldens/shell_narrow_large_text.png'),
    );
  });
}

Future<void> _pumpGolden(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    CommunicationPlatformApp(
      environment: AppEnvironment.production,
      locale: locale,
      themeMode: themeMode,
    ),
  );
  await tester.pumpAndSettle();
}
