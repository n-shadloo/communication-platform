import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/features/messaging/presentation/chat_pages.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  testWidgets('narrow English chat states', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    await expectLater(
      find.byKey(const ValueKey('chat-interface-golden')),
      matchesGoldenFile('goldens/chat_narrow_ltr.png'),
    );
  });

  testWidgets('medium Persian high contrast chat', (tester) async {
    await _pump(
      tester,
      size: const Size(800, 900),
      locale: const Locale('fa'),
      highContrast: true,
    );
    await expectLater(
      find.byKey(const ValueKey('chat-interface-golden')),
      matchesGoldenFile('goldens/chat_medium_rtl_high_contrast.png'),
    );
  });

  testWidgets('wide English dark chat', (tester) async {
    await _pump(tester, size: const Size(1440, 900), themeMode: ThemeMode.dark);
    await expectLater(
      find.byKey(const ValueKey('chat-interface-golden')),
      matchesGoldenFile('goldens/chat_wide_dark.png'),
    );
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  bool highContrast = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        theme: highContrast ? AppTheme.highContrastLight() : AppTheme.light(),
        darkTheme: highContrast ? AppTheme.highContrastDark() : AppTheme.dark(),
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            AppDesignSystem(child: child ?? const SizedBox.shrink()),
        home: ChatConversationView(model: _model(), onIntent: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ChatTimelineViewModel _model() => ChatTimelineViewModel(
  state: ChatTimelineLoadState.data,
  conversationId: 'golden-conversation',
  title: 'Niloofar',
  savedMessages: false,
  securityGate: ChatSecurityGate.ready,
  offline: true,
  hasMoreBefore: true,
  loadingBefore: false,
  olderLoadFailed: false,
  typing: false,
  pinnedMessageIds: const ['00000000000000000000000000000002'],
  messages: [
    _message(
      1,
      text: 'Can you review the deployment notes?',
      outgoing: false,
      delivery: ChatDeliveryViewState.received,
      unread: true,
    ),
    _message(
      2,
      text: 'بله، نسخهٔ رمزنگاری‌شده را همین‌جا بفرست.',
      delivery: ChatDeliveryViewState.delivered,
      pinned: true,
      edited: true,
    ),
    _message(
      3,
      text: 'The relay accepted this while the device was offline.',
      delivery: ChatDeliveryViewState.queued,
    ),
    _message(
      4,
      text: 'This send needs attention.',
      delivery: ChatDeliveryViewState.failed,
    ),
  ],
);

ChatMessageViewModel _message(
  int index, {
  required String text,
  ChatDeliveryViewState delivery = ChatDeliveryViewState.accepted,
  bool outgoing = true,
  bool unread = false,
  bool pinned = false,
  bool edited = false,
}) => ChatMessageViewModel(
  id: index.toRadixString(16).padLeft(32, '0'),
  authorId: outgoing ? 'self' : 'peer',
  authorName: outgoing ? 'You' : 'Niloofar',
  outgoing: outgoing,
  kind: ChatTimelineContentKind.text,
  text: text,
  timestamp: DateTime(2026, 7, 30, 14, index * 3),
  delivery: delivery,
  firstInAuthorGroup: true,
  lastInAuthorGroup: true,
  edited: edited,
  deleted: false,
  pinned: pinned,
  starred: false,
  unread: unread,
  timestampSkewed: false,
  canEdit: outgoing,
  canDeleteForEveryone: outgoing,
  reactions: index == 2
      ? const [
          ChatReactionViewModel(
            emoji: '👍',
            count: 2,
            selectedByCurrentUser: true,
          ),
        ]
      : const [],
);
