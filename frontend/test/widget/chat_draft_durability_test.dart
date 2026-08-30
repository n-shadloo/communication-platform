import 'dart:async';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/features/messaging/presentation/chat_composer_builder.dart';
import 'package:communication_platform/features/messaging/presentation/chat_conversation_view.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a debounced draft owes the person typing it.
///
/// The debounce is the cheap half of the change and the flush contract is the
/// dangerous half: a draft that is written half a second late is fine, and a
/// draft whose last four characters are dropped because the user switched
/// applications is worse than the writes the debounce removed. Every way out
/// of the composer is driven here.
void main() {
  testWidgets('a burst of typing is one write and not one per character', (
    tester,
  ) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    final field = find.byKey(const ValueKey('chat-composer-field'));

    for (final text in ['h', 'he', 'hel', 'hell', 'hello']) {
      await tester.enterText(field, text);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(drafts, isEmpty);

    await tester.pump(ChatComposerBuilderState.draftDebounce);
    expect(drafts, ['hello']);

    // And a settled draft is not written again for having been looked at.
    await tester.pump(ChatComposerBuilderState.draftDebounce);
    expect(drafts, ['hello']);
  });

  testWidgets('losing focus writes the draft down', (tester) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'unfinished',
    );
    await tester.pump();
    expect(drafts, isEmpty);

    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
    expect(drafts, ['unfinished']);
  });

  testWidgets('leaving the foreground writes the draft down', (tester) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'switching away mid-sentence',
    );
    await tester.pump();
    expect(drafts, isEmpty);

    // The transition the debounce would otherwise lose: the process can be
    // killed from here without ever coming back.
    await _lifecycle(tester, AppLifecycleState.inactive);
    await tester.pump();
    expect(drafts, ['switching away mid-sentence']);

    await _lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(drafts, ['switching away mid-sentence']);
  });

  testWidgets('popping the route writes the draft down', (tester) async {
    final drafts = <String?>[];
    final navigator = GlobalKey<NavigatorState>();
    await _pump(tester, onDraft: drafts.add, navigatorKey: navigator);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'typed and then dismissed',
    );
    await tester.pump();
    expect(drafts, isEmpty);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(drafts, ['typed and then dismissed']);
  });

  testWidgets('disposing the composer writes the draft down', (tester) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer-field')),
      'never left the field',
    );
    await tester.pump();
    expect(drafts, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(drafts, ['never left the field']);
  });

  testWidgets('sending clears the stored draft without waiting', (
    tester,
  ) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    final field = find.byKey(const ValueKey('chat-composer-field'));
    await tester.enterText(field, 'ready to go');
    await tester.pump(ChatComposerBuilderState.draftDebounce);
    expect(drafts, ['ready to go']);

    await tester.tap(_sendButton);
    await tester.pump();

    // Not half a second later: a conversation reopened inside that window
    // would have shown the message back as an unsent draft.
    expect(drafts, ['ready to go', null]);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    // The button's own press animation, which outlives the frame the tap
    // landed on and has nothing to do with the draft.
    await tester.pumpAndSettle(const Duration(milliseconds: 150));
    expect(drafts, ['ready to go', null]);
  });

  testWidgets('a draft that arrives after the first build is adopted', (
    tester,
  ) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    final field = find.byKey(const ValueKey('chat-composer-field'));
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    // The stored draft is read once and lands a frame or two after the page
    // is first drawn, which is the whole reason it may be a one-shot read.
    await _pump(tester, onDraft: drafts.add, initialDraft: 'left mid-word');
    expect(tester.widget<TextField>(field).controller!.text, 'left mid-word');

    // Restoring it is not a change to it.
    await tester.pump(ChatComposerBuilderState.draftDebounce);
    expect(drafts, isEmpty);
  });

  testWidgets('a draft that arrives late does not overwrite what was typed', (
    tester,
  ) async {
    final drafts = <String?>[];
    await _pump(tester, onDraft: drafts.add);
    final field = find.byKey(const ValueKey('chat-composer-field'));
    await tester.enterText(field, 'what the user is writing now');
    await tester.pump();

    await _pump(tester, onDraft: drafts.add, initialDraft: 'stale and stored');
    expect(
      tester.widget<TextField>(field).controller!.text,
      'what the user is writing now',
    );
    await tester.pump(ChatComposerBuilderState.draftDebounce);
    expect(drafts, ['what the user is writing now']);
  });
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.lifecycle.name,
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );

final _sendButton = find.byWidgetPredicate(
  (widget) =>
      widget is AppIconButton &&
      widget.icon == AppIcons.send &&
      widget.onPressed != null,
);

Future<void> _pump(
  WidgetTester tester, {
  required ValueChanged<String?> onDraft,
  String? initialDraft,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final view = ChatConversationView(
    model: _model(),
    initialDraft: initialDraft,
    onIntent: (intent) {
      if (intent case SaveDraftIntent(:final text)) onDraft(text);
    },
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          AppDesignSystem(child: child ?? const SizedBox.shrink()),
      home: navigatorKey == null
          ? view
          : _PushOnce(navigatorKey: navigatorKey, child: view),
    ),
  );
  await tester.pumpAndSettle();
}

/// A first route the conversation can be pushed on top of, so that popping it
/// is a real pop rather than an attempt to pop the last route in the stack.
class _PushOnce extends StatefulWidget {
  const _PushOnce({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<_PushOnce> createState() => _PushOnceState();
}

class _PushOnceState extends State<_PushOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        widget.navigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => widget.child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}

ChatTimelineViewModel _model() => ChatTimelineViewModel(
  state: ChatTimelineLoadState.data,
  conversationId: 'conversation',
  title: 'Peer',
  savedMessages: false,
  securityGate: ChatSecurityGate.ready,
  offline: false,
  hasMoreBefore: false,
  loadingBefore: false,
  olderLoadFailed: false,
  typing: false,
  pinnedMessages: const [],
  messages: [
    ChatMessageViewModel(
      id: '0' * 32,
      authorId: 'peer',
      authorName: 'Peer',
      outgoing: false,
      kind: ChatTimelineContentKind.text,
      text: 'the one message this screen needs to be a conversation',
      timestamp: DateTime(2026, 7, 30, 10),
      delivery: ChatDeliveryViewState.received,
      firstInAuthorGroup: true,
      lastInAuthorGroup: true,
      edited: false,
      deleted: false,
      pinned: false,
      starred: false,
      unread: false,
      timestampSkewed: false,
      canEdit: false,
      canDeleteForEveryone: false,
    ),
  ],
);
