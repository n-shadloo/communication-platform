import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The re-viewable half of the ADR-045 disclosure model.
///
/// The notice is acknowledged once, during enrollment, and is deliberately
/// never repeated on a timer. That only works if it stays readable on demand,
/// so these tests hold the entry points open.
void main() {
  testWidgets('the notice is reachable without authentication wiring', (
    tester,
  ) async {
    await _pump(tester, AppEnvironment.production);

    expect(
      find.byKey(const ValueKey('preauth-security-notice')),
      findsOneWidget,
    );
    expect(
      find.text("What this app protects — and what it doesn't"),
      findsOneWidget,
    );
    expect(find.text('What it DOES protect'), findsOneWidget);
    expect(find.text('What it does NOT protect'), findsOneWidget);
  });

  testWidgets('re-reading the notice offers nothing to acknowledge', (
    tester,
  ) async {
    await _pump(tester, AppEnvironment.beta);

    // Acknowledgement belongs to the enrollment gate alone. A second "I
    // understand" here would be a consent the app does not record and does not
    // act on.
    expect(find.text('I understand'), findsNothing);
    expect(find.text('Back'), findsWidgets);
  });

  testWidgets('the re-viewable notice carries the same build disclosure', (
    tester,
  ) async {
    await _pump(tester, AppEnvironment.beta);

    expect(find.byKey(const ValueKey('deployment-disclosure')), findsOneWidget);
    expect(find.text('What this build is'), findsOneWidget);
    expect(
      find.textContaining('Nobody outside the project has reviewed'),
      findsOneWidget,
    );
  });

  testWidgets('production re-reads the permanent boundary and nothing else', (
    tester,
  ) async {
    await _pump(tester, AppEnvironment.production);

    expect(find.byKey(const ValueKey('deployment-disclosure')), findsNothing);
    expect(find.textContaining('What this build is'), findsNothing);
  });

  testWidgets('Settings re-opens the notice', (tester) async {
    await _pump(tester, AppEnvironment.beta, initialLocation: '/settings');

    final entry = find.byKey(const ValueKey('settings-security-notice'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('preauth-security-notice')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('deployment-disclosure')), findsOneWidget);
  });

  testWidgets('the notice is translated, not left in English', (tester) async {
    await _pump(tester, AppEnvironment.beta, locale: const Locale('fa'));

    expect(find.byKey(const ValueKey('deployment-disclosure')), findsOneWidget);
    expect(find.text('این نسخه چیست'), findsOneWidget);
    expect(find.textContaining('What this build is'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppEnvironment environment, {
  String initialLocation = '/security-notice',
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      // `bootstrap()` sets both of these from one argument, and
      // `app_bootstrap_test.dart` holds them together.
      overrides: [appEnvironmentProvider.overrideWithValue(environment)],
      child: CommunicationPlatformApp(
        environment: environment,
        locale: locale,
        initialLocation: initialLocation,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
