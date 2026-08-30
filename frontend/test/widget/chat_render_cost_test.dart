import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/application/conversation_timeline.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_conversation_domain_repository.dart';
import 'package:communication_platform/features/messaging/presentation/chat_composer_builder.dart';
import 'package:communication_platform/features/messaging/presentation/chat_conversation_view.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_model_mapper.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/conversation_history_harness.dart';

const _conversationId = 'conversation';

/// What one thing happening costs the screen.
///
/// The repository, the window, the projection and the whole conversation view
/// are real here, against a real database, because the claim is about the seam
/// between them: an emission arrives as freshly allocated rows whatever changed
/// in it, and everything downstream — how many view models are derived, how
/// many rows are redrawn, whether the page rebuilds at all — used to be decided
/// by the size of the window rather than by the size of the change.
///
/// The counts are asserted as *equalities across two window sizes*, in the
/// discipline ADR-061, ADR-062 and ADR-063 established, so a re-derivation
/// finding its way back onto this path fails loudly rather than gradually.
void main() {
  group('deriving view models', () {
    late LocalDatabase database;
    late DriftConversationDomainRepository repository;
    late ConversationTimelineWindow window;

    Future<_PageHarnessState> open(
      WidgetTester tester, {
      required int messages,
      required int pages,
    }) async {
      await seedConversationHistory(
        database,
        conversationId: _conversationId,
        messages: messages,
        withChildren: false,
      );
      window = ConversationTimelineWindow(
        repository: repository,
        currentUserId: 'self',
        conversationId: _conversationId,
        pageSize: 40,
      );
      final state = await _pump(tester, window, repository);
      for (var page = 0; page < pages; page++) {
        await window.loadOlder();
        await tester.pumpAndSettle();
      }
      return state;
    }

    setUp(() async {
      database = LocalDatabase(NativeDatabase.memory());
      await database.customSelect('SELECT 1').getSingle();
      repository = DriftConversationDomainRepository(database);
    });

    tearDown(() async {
      await window.dispose();
      await database.close();
    });

    for (final scenario in const [
      (name: 'a 48-message window', messages: 48, pages: 1, loaded: 48),
      (name: 'a 240-message window', messages: 1200, pages: 5, loaded: 240),
    ]) {
      testWidgets('one message arriving into ${scenario.name} derives two', (
        tester,
      ) async {
        final harness = await open(
          tester,
          messages: scenario.messages,
          pages: scenario.pages,
        );
        expect(harness.messages.length, scenario.loaded);

        // What the same emission costs a mapper with nothing to compare it
        // against, which is what this page did on every emission.
        final control = ChatMessageProjection()
          ..map(
            harness.page,
            currentUserId: 'self',
            currentUserName: 'You',
            peerName: 'Peer',
          );
        expect(control.derivations, scenario.loaded);

        final derivations = harness.projection.derivations;
        final builds = harness.builds;
        await appendConversationMessage(
          database,
          conversationId: _conversationId,
          index: scenario.messages,
        );
        await tester.pumpAndSettle();

        expect(harness.messages.length, scenario.loaded + 1);
        // The message that arrived, and the one it is now grouped with. Not
        // the window it arrived into.
        expect(harness.projection.derivations - derivations, 2);
        expect(harness.builds - builds, 1);
      });

      testWidgets('one reaction on ${scenario.name} derives one', (
        tester,
      ) async {
        final harness = await open(
          tester,
          messages: scenario.messages,
          pages: scenario.pages,
        );
        final target = harness.messages.last.id;
        final derivations = harness.projection.derivations;
        final builds = harness.builds;

        await _react(database, messageId: target);
        await tester.pumpAndSettle();

        expect(harness.messages.last.reactions.single.emoji, '\u{1F44D}');
        expect(harness.projection.derivations - derivations, 1);
        expect(harness.builds - builds, 1);
      });

      testWidgets('one keystroke into ${scenario.name} derives none', (
        tester,
      ) async {
        final harness = await open(
          tester,
          messages: scenario.messages,
          pages: scenario.pages,
        );
        final derivations = harness.projection.derivations;
        final builds = harness.builds;

        await tester.enterText(
          find.byKey(const ValueKey('chat-composer-field')),
          'a',
        );
        await tester.pump();

        expect(harness.projection.derivations - derivations, 0);
        expect(harness.builds - builds, 0);

        // And the write the keystroke eventually causes does not reach the
        // timeline either: a draft lives in the `conversations` row, which is
        // not what a conversation's messages are read through.
        await tester.pump(ChatComposerBuilderState.draftDebounce);
        await tester.pumpAndSettle();
        expect(harness.intents.whereType<SaveDraftIntent>().single.text, 'a');
        expect(harness.projection.derivations - derivations, 0);
        expect(harness.builds - builds, 0);
      });
    }
  });

  group('what a draft write invalidates', () {
    late LocalDatabase database;

    setUp(() async {
      database = LocalDatabase(NativeDatabase.memory());
      await database.customSelect('SELECT 1').getSingle();
      await seedConversationHistory(
        database,
        conversationId: _conversationId,
        messages: 20,
        withChildren: false,
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('the conversation list, and not the open conversation', () async {
      final container = ProviderContainer(
        overrides: [
          localDatabaseProvider.overrideWith((ref) => Future.value(database)),
        ],
      );
      addTearDown(container.dispose);
      const request = (currentUserId: 'self', conversationId: _conversationId);

      var summaries = 0;
      var messages = 0;
      container.listen(conversationSummariesProvider('self'), (_, next) {
        if (next.hasValue) summaries += 1;
      }, fireImmediately: true);
      container.listen(conversationMessagesProvider(request), (_, next) {
        if (next.hasValue) messages += 1;
      }, fireImmediately: true);
      await container.read(conversationSummariesProvider('self').future);
      await container.read(conversationMessagesProvider(request).future);
      final summariesBefore = summaries;
      final messagesBefore = messages;

      final repository = DriftConversationDomainRepository(database);
      await repository.saveDraft(
        conversationId: _conversationId,
        text: 'half a sentence',
      );
      await pumpEventQueue();

      // This is the cascade the chat page used to sit at the end of: a draft
      // write touches the `conversations` row, so the list re-emits. The
      // timeline is read through `messages` and does not.
      expect(summaries - summariesBefore, greaterThanOrEqualTo(1));
      expect(messages - messagesBefore, 0);
    });
  });
}

/// One reaction, written the shape the projector writes it.
///
/// The reaction row and a rewrite of the message it is about: an incremental
/// apply re-folds the message it received a fact about (ADR-063), and the
/// message row is what the timeline is read through.
Future<void> _react(LocalDatabase database, {required String messageId}) async {
  await database
      .into(database.messageReactions)
      .insert(
        MessageReactionsCompanion.insert(
          messageId: messageId,
          reactingUserId: 'peer',
          eventId: 'reaction-$messageId',
          emojiCiphertext: Value(Uint8List.fromList(utf8.encode('\u{1F44D}'))),
        ),
      );
  await (database.update(database.messages)
        ..where((row) => row.messageId.equals(messageId)))
      .write(const MessagesCompanion(status: Value(3)));
}

Future<_PageHarnessState> _pump(
  WidgetTester tester,
  ConversationTimelineWindow window,
  ConversationRepositoryPort repository,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(430, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          AppDesignSystem(child: child ?? const SizedBox.shrink()),
      home: _PageHarness(window: window, repository: repository),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<_PageHarnessState>(find.byType(_PageHarness));
}

/// The chat page's half of the contract: one projection, held open.
class _PageHarness extends StatefulWidget {
  const _PageHarness({required this.window, required this.repository});

  final ConversationTimelineWindow window;
  final ConversationRepositoryPort repository;

  @override
  State<_PageHarness> createState() => _PageHarnessState();
}

class _PageHarnessState extends State<_PageHarness> {
  final ChatMessageProjection projection = ChatMessageProjection();
  final List<ChatIntent> intents = <ChatIntent>[];
  var builds = 0;
  ConversationTimelineState? _state;
  StreamSubscription<ConversationTimelineState>? _subscription;
  List<ChatMessageViewModel> _messages = const [];

  List<ChatMessageViewModel> get messages => _messages;

  List<ConversationMessage> get page => _state?.page.messages ?? const [];

  @override
  void initState() {
    super.initState();
    _subscription = widget.window.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds += 1;
    final state = _state;
    if (state == null) return const SizedBox.shrink();
    _messages = projection.map(
      state.page.messages,
      currentUserId: 'self',
      currentUserName: 'You',
      peerName: 'Peer',
    );
    return ChatConversationView(
      model: ChatTimelineViewModel(
        state: _messages.isEmpty
            ? ChatTimelineLoadState.empty
            : ChatTimelineLoadState.data,
        conversationId: _conversationId,
        title: 'Peer',
        savedMessages: false,
        securityGate: ChatSecurityGate.ready,
        offline: false,
        hasMoreBefore: state.page.hasMoreBefore,
        loadingBefore: state.loadingBefore,
        olderLoadFailed: state.olderLoadFailed,
        typing: false,
        pinnedMessages: const [],
        messages: _messages,
      ),
      onIntent: (intent) {
        intents.add(intent);
        if (intent case SaveDraftIntent(:final text)) {
          unawaited(
            widget.repository.saveDraft(
              conversationId: _conversationId,
              text: text,
            ),
          );
        }
      },
    );
  }
}
