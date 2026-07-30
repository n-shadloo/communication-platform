import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selects narrow, medium, and wide structures by measured width', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(360, 800));
    expect(find.byKey(const ValueKey('shell-narrow')), findsOneWidget);

    await _resize(tester, const Size(800, 900));
    expect(find.byKey(const ValueKey('shell-medium')), findsOneWidget);

    await _resize(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('shell-wide')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves a nested route while resizing across breakpoints', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: const Size(360, 800),
      initialLocation: '/voice-rooms/sample-room',
    );
    expect(find.text('Route: /voice-rooms/sample-room'), findsOneWidget);

    await _resize(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('shell-wide')), findsOneWidget);
    expect(find.text('Route: /voice-rooms/sample-room'), findsOneWidget);
  });

  testWidgets('keyboard shortcuts navigate the stable destination set', (
    tester,
  ) async {
    await _pumpApp(tester, size: const Size(1440, 900));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.text('Voice Rooms structure'), findsOneWidget);
    expect(find.text('Route: /voice-rooms'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('Settings structure'), findsOneWidget);
  });

  testWidgets('guard hook can reject a protected destination', (tester) async {
    await _pumpApp(tester, size: const Size(1440, 900), guardSettings: true);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.text('Settings structure'), findsNothing);
  });

  testWidgets('large text on an Android-sized viewport does not overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, size: const Size(360, 800));

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Voice Rooms'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Start a chat'));
    await tester.pumpAndSettle();
    expect(find.text('Start a chat').hitTestable(), findsOneWidget);
  });

  testWidgets('dark and authored high-contrast themes expose semantic tokens', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      size: const Size(800, 900),
      themeMode: ThemeMode.dark,
    );
    var context = tester.element(
      find.byKey(const ValueKey('chats-list-screen')),
    );
    expect(context.tokens.colors.canvas, const Color(0xFF0E1014));
    expect(context.tokens.colors.accent, const Color(0xFF8298FF));

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      const CommunicationPlatformApp(
        environment: AppEnvironment.production,
        locale: Locale('en'),
        themeMode: ThemeMode.light,
      ),
    );
    await tester.pumpAndSettle();
    context = tester.element(find.byKey(const ValueKey('chats-list-screen')));
    expect(context.tokens.colors.canvas, Colors.white);
    expect(context.tokens.colors.border, Colors.black);
  });

  testWidgets('reduced motion removes spatial route travel', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          disableAnimations: true,
          reduceMotion: true,
        );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester, size: const Size(360, 800));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Voice Rooms structure'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-route-spatial-transition')),
      findsNothing,
    );
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  ThemeMode themeMode = ThemeMode.light,
  String initialLocation = '/chats',
  bool guardSettings = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    CommunicationPlatformApp(
      environment: AppEnvironment.production,
      locale: const Locale('en'),
      themeMode: themeMode,
      initialLocation: initialLocation,
      routeGuard: guardSettings
          ? (context, state) =>
                state.uri.path.startsWith('/settings') ? '/chats' : null
          : null,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}
