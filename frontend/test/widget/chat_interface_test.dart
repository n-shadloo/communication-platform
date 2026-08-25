import 'dart:math' as math;

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/features/messaging/presentation/chat_pages.dart';
import 'package:communication_platform/features/messaging/presentation/chat_timeline.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders every honest transport state with text semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final states = ChatDeliveryViewState.values;
    await _pump(
      tester,
      ChatConversationView(
        model: _model(
          messages: [
            for (var index = 0; index < states.length; index++)
              _message(
                index,
                delivery: states[index],
                text: 'state-${states[index].name}',
                outgoing: true,
              ),
          ],
        ),
        onIntent: (_) {},
      ),
    );

    for (final state in states.where(
      (state) => state != ChatDeliveryViewState.received,
    )) {
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(_deliveryEnglishLabel(state))),
        ),
        findsWidgets,
      );
    }
    expect(find.text('state-failed'), findsOneWidget);
    expect(find.text('Retry as a new encrypted send'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('withholds composer for every blocking security condition', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final gate in ChatSecurityGate.values.where(
      (gate) =>
          gate != ChatSecurityGate.ready && gate != ChatSecurityGate.checking,
    )) {
      await _pump(
        tester,
        ChatConversationView(
          model: _model(securityGate: gate),
          onIntent: (_) {},
        ),
      );
      expect(
        find.byKey(const ValueKey('chat-composer-field')),
        findsNothing,
        reason: gate.name,
      );
      expect(
        find.bySemanticsLabel(RegExp('Messaging withheld')),
        findsWidgets,
        reason: gate.name,
      );
    }
    semantics.dispose();
  });

  testWidgets('holds the composer inert while the trust state is unread', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      ChatConversationView(
        model: _model(securityGate: ChatSecurityGate.checking),
        onIntent: (_) {},
      ),
    );
    // The composer keeps its place so opening a chat does not shuffle its
    // layout, and says nothing about the peer while nothing is known.
    final field = find.byKey(const ValueKey('chat-composer-field'));
    expect(field, findsOneWidget);
    expect(tester.widget<TextField>(field).enabled, isFalse);
    expect(find.bySemanticsLabel(RegExp('Messaging withheld')), findsNothing);
    semantics.dispose();
  });

  testWidgets('composer dispatches typed reply, edit, and send intents', (
    tester,
  ) async {
    final intents = <ChatIntent>[];
    await _pump(
      tester,
      ChatConversationView(model: _model(), onIntent: intents.add),
    );
    intents.clear();

    await tester.longPress(find.text('message-5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply').last);
    await tester.pumpAndSettle();
    expect(find.text('Replying to Peer'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'reply body',
    );
    await tester.pump();
    expect(_sendButton, findsOneWidget);
    await tester.tap(_sendButton);
    await tester.pump();
    expect(intents.whereType<SendTextIntent>().last.replyToMessageId, _id(5));

    await tester.longPress(find.text('message-4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(find.text('Editing message'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'edited body',
    );
    await tester.pump();
    expect(_sendButton, findsOneWidget);
    await tester.tap(_sendButton);
    await tester.pumpAndSettle();
    expect(intents.whereType<EditMessageIntent>().last.messageId, _id(4));
  });

  testWidgets('message menu is keyboard reachable and exposes actions', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatConversationView(model: _model(), onIntent: (_) {}),
    );
    final message = find.byKey(ValueKey('message-${_id(5)}'));
    final focus = find
        .descendant(of: message, matching: find.byType(Focus))
        .first;
    Focus.of(tester.element(focus)).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Message actions'), findsWidgets);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('forward picker dispatches immutable targets as a typed intent', (
    tester,
  ) async {
    final intents = <ChatIntent>[];
    await _pump(
      tester,
      ChatConversationView(
        model: _model(),
        forwardTargets: [
          ChatListItemViewModel(
            conversationId: '',
            title: 'Saved Messages',
            preview: '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            unreadCount: 0,
            muted: false,
            pinned: false,
            savedMessages: true,
            peerUserId: null,
          ),
        ],
        onIntent: intents.add,
      ),
    );
    intents.clear();

    await tester.longPress(find.text('message-5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved Messages').last);
    await tester.pump();
    await tester.tap(find.text('Forward').last);
    await tester.pumpAndSettle();

    final forwarded = intents.whereType<ForwardToConversationsIntent>().single;
    expect(forwarded.message.id, _id(5));
    expect(forwarded.targets.single.savedMessages, isTrue);
  });

  testWidgets('upward pagination keeps the visible reading anchor', (
    tester,
  ) async {
    final allMessages = [
      for (var index = 0; index < 240; index++) _message(index),
    ];
    final page = ValueNotifier<List<ChatMessageViewModel>>(
      allMessages.sublist(210),
    );
    addTearDown(page.dispose);
    await _pump(
      tester,
      ValueListenableBuilder<List<ChatMessageViewModel>>(
        valueListenable: page,
        builder: (context, messages, _) => SizedBox(
          height: 620,
          child: ChatTimelineAdapter(
            model: _model(messages: messages),
            onIntent: (_) {},
            initialPageSize: 80,
          ),
        ),
      ),
    );
    final anchor = find.byKey(ValueKey('message-${_id(235)}'));
    expect(anchor, findsOneWidget);
    final before = tester.getTopLeft(anchor).dy;

    page.value = allMessages.sublist(180);
    await tester.pump();
    final after = tester.getTopLeft(anchor).dy;
    expect((after - before).abs(), lessThan(1.1));
  });

  testWidgets('edits, reactions, and resize preserve a reading anchor', (
    tester,
  ) async {
    final original = [for (var index = 0; index < 60; index++) _message(index)];
    final page = ValueNotifier<List<ChatMessageViewModel>>(original);
    addTearDown(page.dispose);
    await _pump(
      tester,
      ValueListenableBuilder<List<ChatMessageViewModel>>(
        valueListenable: page,
        builder: (context, messages, _) => ChatTimelineAdapter(
          model: _model(messages: messages),
          onIntent: (_) {},
        ),
      ),
    );
    await tester.drag(
      find.byKey(const PageStorageKey('chat-timeline')),
      // The timeline is reversed: dragging content toward the bottom moves the
      // reading position into older history.
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();

    final visible = tester
        .widgetList<ChatMessageBuilder>(find.byType(ChatMessageBuilder))
        .where((builder) {
          final finder = find.byKey(ValueKey('message-${builder.message.id}'));
          if (finder.evaluate().isEmpty) return false;
          final y = tester.getTopLeft(finder).dy;
          return y > 80 && y < 680;
        })
        .first;
    final anchor = find.byKey(ValueKey('message-${visible.message.id}'));
    final before = tester.getTopLeft(anchor).dy;

    page.value = [
      ...original.take(59),
      _message(
        59,
        text: List.filled(20, 'expanded edit').join(' '),
        edited: true,
        reactions: const [
          ChatReactionViewModel(
            emoji: '👍',
            count: 12,
            selectedByCurrentUser: false,
          ),
        ],
      ),
    ];
    await tester.pump();
    await tester.pump();
    expect((tester.getTopLeft(anchor).dy - before).abs(), lessThan(1.1));

    tester.view.physicalSize = const Size(600, 900);
    await tester.pump();
    await tester.pump();
    expect((tester.getTopLeft(anchor).dy - before).abs(), lessThan(1.1));
  });

  testWidgets('50,000-message fixture keeps mounted widgets bounded', (
    tester,
  ) async {
    final stopwatch = Stopwatch()..start();
    final messages = [
      for (var index = 0; index < 50000; index++) _message(index),
    ];
    await _pump(
      tester,
      ChatTimelineAdapter(
        model: _model(messages: messages),
        onIntent: (_) {},
      ),
      settle: false,
    );
    await tester.pump();
    stopwatch.stop();

    expect(find.byType(ChatMessageBuilder), findsWidgets);
    expect(
      tester
          .widgetList<ChatMessageBuilder>(find.byType(ChatMessageBuilder))
          .length,
      lessThan(40),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  for (final scenario in <_Scenario>[
    const _Scenario('narrow English', Size(360, 800)),
    const _Scenario('medium Persian', Size(800, 900), locale: Locale('fa')),
    const _Scenario('wide dark', Size(1440, 900), themeMode: ThemeMode.dark),
    const _Scenario('narrow high contrast', Size(390, 844), highContrast: true),
    const _Scenario(
      'large text reduced motion',
      Size(430, 900),
      textScale: 2,
      reducedMotion: true,
    ),
  ]) {
    testWidgets('${scenario.name} remains usable without overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        ChatConversationView(model: _model(), onIntent: (_) {}),
        size: scenario.size,
        locale: scenario.locale,
        themeMode: scenario.themeMode,
        highContrast: scenario.highContrast,
        textScale: scenario.textScale,
        reducedMotion: scenario.reducedMotion,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('direct-chat-screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
      final direction = tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection;
      expect(
        direction,
        scenario.locale.languageCode == 'fa'
            ? TextDirection.rtl
            : TextDirection.ltr,
      );
    });
  }

  testWidgets('Saved Messages has no peer presence or receipt promise', (
    tester,
  ) async {
    await _pump(
      tester,
      SavedMessagesPage(
        injectedModel: _model(savedMessages: true),
        onIntent: (_) {},
      ),
    );
    expect(find.text('Saved Messages'), findsWidgets);
    expect(find.textContaining('online via'), findsNothing);
    expect(find.textContaining('typing'), findsNothing);
    expect(find.text('Write a note to yourself'), findsOneWidget);
  });

  testWidgets('Chats List exposes loading, empty, error, offline and rows', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatsListPage(
        model: ChatListViewModel(
          items: [
            ChatListItemViewModel(
              conversationId: 'conversation',
              title: 'Peer',
              preview: 'Last encrypted message',
              timestamp: DateTime(2026, 7, 30, 12),
              unreadCount: 3,
              muted: true,
              pinned: true,
              savedMessages: false,
              peerUserId: 'peer',
            ),
          ],
          loading: false,
          offline: true,
          failed: false,
        ),
      ),
    );
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('showing cached conversations'), findsOneWidget);

    await _pump(
      tester,
      ChatsListPage(
        model: ChatListViewModel(
          items: const [],
          loading: false,
          offline: false,
          failed: false,
        ),
      ),
    );
    expect(find.text('No chats yet'), findsOneWidget);

    await _pump(
      tester,
      ChatsListPage(
        model: ChatListViewModel(
          items: const [],
          loading: false,
          offline: false,
          failed: true,
        ),
      ),
    );
    expect(find.text('Chats are unavailable'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(430, 900),
  Locale locale = const Locale('en'),
  ThemeMode themeMode = ThemeMode.light,
  bool highContrast = false,
  double textScale = 1,
  bool reducedMotion = false,
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(
        highContrast: highContrast,
        disableAnimations: reducedMotion,
      );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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
        home: child,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

ChatTimelineViewModel _model({
  Iterable<ChatMessageViewModel>? messages,
  ChatSecurityGate securityGate = ChatSecurityGate.ready,
  bool savedMessages = false,
}) {
  final source =
      messages ??
      [
        for (var index = 0; index < 6; index++)
          _message(
            index,
            outgoing: index.isEven,
            unread: index == 3,
            pinned: index == 2,
            edited: index == 4,
            reactions: index == 5
                ? const [
                    ChatReactionViewModel(
                      emoji: '👍',
                      count: 2,
                      selectedByCurrentUser: true,
                    ),
                  ]
                : const [],
            replyToMessageId: index == 5 ? _id(2) : null,
            replyQuote: index == 5 ? 'message-2' : null,
          ),
      ];
  final list = List<ChatMessageViewModel>.unmodifiable(source);
  return ChatTimelineViewModel(
    state: list.isEmpty
        ? ChatTimelineLoadState.empty
        : ChatTimelineLoadState.data,
    conversationId: 'conversation',
    title: savedMessages ? 'Saved Messages' : 'Peer',
    savedMessages: savedMessages,
    securityGate: securityGate,
    offline: false,
    hasMoreBefore: false,
    loadingBefore: false,
    olderLoadFailed: false,
    presenceOnline: !savedMessages,
    typing: false,
    pinnedMessageIds: [
      for (final message in list)
        if (message.pinned) message.id,
    ],
    messages: list,
  );
}

ChatMessageViewModel _message(
  int index, {
  ChatDeliveryViewState delivery = ChatDeliveryViewState.accepted,
  String? text,
  bool? outgoing,
  bool unread = false,
  bool pinned = false,
  bool edited = false,
  Iterable<ChatReactionViewModel> reactions = const [],
  String? replyToMessageId,
  String? replyQuote,
}) {
  final isOutgoing = outgoing ?? index.isEven;
  return ChatMessageViewModel(
    id: _id(index),
    authorId: isOutgoing ? 'self' : 'peer',
    authorName: isOutgoing ? 'You' : 'Peer',
    outgoing: isOutgoing,
    kind: ChatTimelineContentKind.text,
    text: text ?? 'message-$index',
    timestamp: DateTime(
      2026,
      7,
      30,
      10,
    ).add(Duration(minutes: math.min(index, 100000))),
    delivery: isOutgoing ? delivery : ChatDeliveryViewState.received,
    firstInAuthorGroup: true,
    lastInAuthorGroup: true,
    edited: edited,
    deleted: false,
    pinned: pinned,
    starred: false,
    unread: unread,
    timestampSkewed: false,
    canEdit: isOutgoing,
    canDeleteForEveryone: isOutgoing,
    replyToMessageId: replyToMessageId,
    replyAuthor: replyToMessageId == null ? null : 'Peer',
    replyQuote: replyQuote,
    reactions: reactions,
  );
}

String _id(int value) => value.toRadixString(16).padLeft(32, '0');

String _deliveryEnglishLabel(ChatDeliveryViewState state) => switch (state) {
  ChatDeliveryViewState.localOnly => 'saved locally only',
  ChatDeliveryViewState.queued => 'queued offline',
  ChatDeliveryViewState.encrypting => 'encrypting',
  ChatDeliveryViewState.sending => 'sending to server',
  ChatDeliveryViewState.accepted => 'accepted by server relay',
  ChatDeliveryViewState.delivered => 'durably delivered to a recipient device',
  ChatDeliveryViewState.read => 'read receipt received',
  ChatDeliveryViewState.failed => 'send failed',
  ChatDeliveryViewState.received => 'received',
};

final Finder _sendButton = find.byWidgetPredicate(
  (widget) =>
      widget is AppIconButton &&
      widget.icon == AppIcons.send &&
      widget.onPressed != null,
);

final class _Scenario {
  const _Scenario(
    this.name,
    this.size, {
    this.locale = const Locale('en'),
    this.themeMode = ThemeMode.light,
    this.highContrast = false,
    this.textScale = 1,
    this.reducedMotion = false,
  });

  final String name;
  final Size size;
  final Locale locale;
  final ThemeMode themeMode;
  final bool highContrast;
  final double textScale;
  final bool reducedMotion;
}
