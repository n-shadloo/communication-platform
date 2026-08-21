import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/message_alerts.dart';
import 'package:communication_platform/features/messaging/presentation/visible_conversation.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:communication_platform/features/notifications/presentation/notification_settings_entry.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two user-facing surfaces this piece adds: the route that says what is on
/// screen, and the Settings row that says what the operating system will do.
void main() {
  group('what is on screen', () {
    testWidgets('a mounted conversation route is what is visible', (
      tester,
    ) async {
      final registry = VisibleConversationRegistry();
      addTearDown(registry.dispose);

      await tester.pumpWidget(
        VisibleConversationScope(
          registry: registry,
          conversationId: 'c1',
          child: const SizedBox.shrink(),
        ),
      );

      expect(registry.conversationId, 'c1');
    });

    testWidgets('leaving the route clears it', (tester) async {
      final registry = VisibleConversationRegistry();
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        VisibleConversationScope(
          registry: registry,
          conversationId: 'c1',
          child: const SizedBox.shrink(),
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());

      expect(registry.conversationId, isNull);
    });

    testWidgets('a replacement route wins over the one it replaced', (
      tester,
    ) async {
      final registry = VisibleConversationRegistry();
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        VisibleConversationScope(
          registry: registry,
          conversationId: 'c1',
          child: const SizedBox.shrink(),
        ),
      );

      await tester.pumpWidget(
        VisibleConversationScope(
          registry: registry,
          conversationId: 'c2',
          child: const SizedBox.shrink(),
        ),
      );

      expect(registry.conversationId, 'c2');
    });

    testWidgets(
      'a route left mounted behind a backgrounded app is not visible',
      (tester) async {
        final registry = VisibleConversationRegistry();
        addTearDown(registry.dispose);
        await tester.pumpWidget(
          VisibleConversationScope(
            registry: registry,
            conversationId: 'c1',
            child: const SizedBox.shrink(),
          ),
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

        expect(registry.conversationId, isNull);
        expect(registry.isForeground, isFalse);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        expect(registry.conversationId, 'c1');
      },
    );

    test('an unreported lifecycle at launch reads as foreground', () {
      // The same trap ADR-047 hit in the delivery path: Flutter leaves
      // `lifecycleState` null until the first platform message, and reading
      // that as backgrounded would announce every message the user is looking
      // at, right up until the first message arrives.
      TestWidgetsFlutterBinding.ensureInitialized();
      final registry = VisibleConversationRegistry(observeLifecycle: false);
      addTearDown(registry.dispose);

      expect(registry.isForeground, isTrue);
    });
  });

  group('the Settings row', () {
    testWidgets('says alerts are on, and what they will and will not say', (
      tester,
    ) async {
      await _pumpRow(tester, enabled: true);

      expect(find.text('Notifications'), findsOneWidget);
      expect(
        find.textContaining('never who sent it or what it says'),
        findsOneWidget,
      );
      expect(
        find.textContaining('only reach you while this app is running'),
        findsOneWidget,
        reason: 'the row may not imply a delivery tier the build does not have',
      );
      expect(find.text('Turn on'), findsNothing);
    });

    testWidgets('offers one action when they are off', (tester) async {
      final presenter = _RecordingPresenter(
        const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        ),
        grantOnRequest: true,
      );
      await _pumpRow(tester, presenter: presenter);

      expect(
        find.textContaining('Nothing will tell you a message arrived'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-notifications-turn-on')),
      );
      await tester.pumpAndSettle();

      expect(presenter.requests, 1);
      expect(
        presenter.settingsOpened,
        0,
        reason: 'the prompt was shown and answered; nothing else is needed',
      );
    });

    testWidgets('falls through to the system settings when asking is spent', (
      tester,
    ) async {
      // Android stops showing the prompt after a second refusal and does not
      // say so. One tap must still end somewhere the user can act.
      final presenter = _RecordingPresenter(
        const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        ),
        grantOnRequest: false,
      );
      await _pumpRow(tester, presenter: presenter);

      await tester.tap(
        find.byKey(const ValueKey('settings-notifications-turn-on')),
      );
      await tester.pumpAndSettle();

      expect(presenter.requests, 1);
      expect(presenter.settingsOpened, 1);
    });

    testWidgets('a build with no implementation says so and offers nothing', (
      tester,
    ) async {
      await _pumpRow(tester, presenter: _RecordingPresenter(null));

      expect(find.text('Not available in this build.'), findsOneWidget);
      expect(find.text('Turn on'), findsNothing);
    });

    testWidgets('the row is translated, not left in English', (tester) async {
      await _pumpRow(tester, enabled: true, locale: const Locale('fa'));

      expect(find.text('اعلان‌ها'), findsOneWidget);
      expect(find.textContaining('Notifications'), findsNothing);
    });
  });
}

Future<void> _pumpRow(
  WidgetTester tester, {
  bool enabled = false,
  _RecordingPresenter? presenter,
  Locale locale = const Locale('en'),
}) async {
  final resolved =
      presenter ??
      _RecordingPresenter(
        MessageAlertPlatformState(
          enabled: enabled,
          runtimePermission: true,
          rationale: false,
        ),
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(AppEnvironment.production),
        messageAlertPresenterProvider.overrideWithValue(resolved),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: NotificationSettingsEntry()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _RecordingPresenter implements MessageAlertPresenterPort {
  _RecordingPresenter(this._state, {this.grantOnRequest = false});

  MessageAlertPlatformState? _state;
  final bool grantOnRequest;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<MessageAlertPlatformState?> platformState() async => _state;

  @override
  Future<MessageAlertPlatformState?> requestPermission() async {
    requests += 1;
    if (grantOnRequest) {
      _state = const MessageAlertPlatformState(
        enabled: true,
        runtimePermission: true,
        rationale: false,
      );
    }
    return _state;
  }

  @override
  Future<void> show(MessageAlertBody body) async {}

  @override
  Future<void> hide() async {}

  @override
  Future<void> openSystemSettings() async => settingsOpened += 1;
}
