import 'dart:async';

import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/app/dependencies/sync_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/attachments/presentation/attachment_sheet.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/presentation/chat_timeline.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_model_mapper.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/features/messaging/presentation/conversation_search.dart';
import 'package:communication_platform/features/messaging/presentation/visible_conversation.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatsListPage extends StatefulWidget {
  const ChatsListPage({
    this.model,
    this.onOpenConversation,
    this.compact = false,
    super.key,
  });

  final ChatListViewModel? model;
  final ValueChanged<ChatListItemViewModel>? onOpenConversation;
  final bool compact;

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final injected = widget.model;
    if (injected != null) return _scaffold(context, injected);
    // App-shell and route harnesses may intentionally render without the
    // production ProviderScope. Keep that presentation-only surface useful
    // while the real bootstrap continues to provide the runtime container.
    try {
      ProviderScope.containerOf(context);
    } on StateError {
      return _scaffold(
        context,
        ChatListViewModel(
          items: const [],
          loading: false,
          offline: false,
          failed: false,
        ),
      );
    }
    return Consumer(builder: (context, ref, _) => _projected(context, ref));
  }

  Widget _projected(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authenticationControllerProvider);
    final currentUserId = auth.userId;
    if (currentUserId == null) {
      return _scaffold(
        context,
        ChatListViewModel(
          items: [],
          loading: false,
          offline: false,
          failed: false,
        ),
      );
    }
    final summaries = ref.watch(conversationSummariesProvider(currentUserId));
    final contacts = ref.watch(contactListProvider(currentUserId));
    // A jammed engine and a slow network used to look identical from here,
    // because nothing in this application read the phase the engine has been
    // writing all along.
    final delivery = _deliveryIndicator(
      ref.watch(syncProjectionProvider).value?.connectionPhase,
    );
    final names = {
      for (final contact in contacts.value ?? const <ContactProjection>[])
        contact.userId: contact.presentationName,
    };
    final strings = AppLocalizations.of(context);
    final model = summaries.when(
      data: (items) => ChatListViewModel(
        items: ChatViewModelMapper.summaries(
          items,
          now: DateTime.now(),
          savedMessagesTitle: strings.savedMessagesTitle,
          peerTitle: (id) => names[id] ?? _shortIdentity(id),
        ),
        loading: false,
        offline: auth.access == AuthenticationRouteAccess.offlineFullScope,
        failed: false,
        delivery: delivery,
      ),
      loading: () => ChatListViewModel(
        items: const [],
        loading: true,
        offline: auth.access == AuthenticationRouteAccess.offlineFullScope,
        failed: false,
        delivery: delivery,
      ),
      error: (_, _) => ChatListViewModel(
        items: const [],
        loading: false,
        offline: auth.access == AuthenticationRouteAccess.offlineFullScope,
        failed: true,
        delivery: delivery,
      ),
    );
    return _scaffold(context, model, ref: ref);
  }

  Widget _scaffold(
    BuildContext context,
    ChatListViewModel model, {
    WidgetRef? ref,
  }) {
    final strings = AppLocalizations.of(context);
    final query = _search.text.trim().toLowerCase();
    final items = model.items
        .where(
          (item) =>
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.preview.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final body = Column(
      children: [
        if (model.offline)
          _InlineNotice(
            key: const ValueKey('chats-offline-notice'),
            label: strings.chatsOfflineCachedNotice,
            kind: AppStatusKind.warning,
          )
        else if (_deliveryNotice(model.delivery, strings) case final label?)
          _InlineNotice(
            key: const ValueKey('chats-delivery-notice'),
            label: label,
            kind: AppStatusKind.neutral,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x3,
            AppSpacing.x4,
            AppSpacing.x2,
          ),
          child: TextField(
            key: const ValueKey('chats-search-field'),
            controller: _search,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: strings.chatsSearchHint,
              prefixIcon: Padding(
                padding: const EdgeInsets.all(AppSpacing.x3),
                child: AppIcon(AppIcons.search),
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : AppIconButton(
                      icon: AppIcons.close,
                      semanticLabel: strings.chatsClearSearchAction,
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      kind: AppButtonKind.ghost,
                    ),
              filled: true,
              fillColor: context.tokens.colors.surfaceRaised,
              border: const OutlineInputBorder(
                borderRadius: AppRadii.control,
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: switch ((model.loading, model.failed, items.isEmpty, query)) {
            (true, _, _, _) => AppStatePanel.loading(
              title: strings.chatsLoadingTitle,
            ),
            (_, true, _, _) => AppStatePanel.error(
              title: strings.chatsErrorTitle,
              message: strings.chatsErrorMessage,
              actionLabel: strings.retryAction,
              onAction: () {
                final userId = ref
                    ?.read(authenticationControllerProvider)
                    .userId;
                if (userId != null) {
                  ref?.invalidate(conversationSummariesProvider(userId));
                }
              },
            ),
            (_, _, true, '') => AppStatePanel.empty(
              title: strings.chatsEmptyTitle,
              message: strings.chatsEmptyMessage,
              actionLabel: strings.chatsStartAction,
              onAction: () => context.go('/chats/new'),
            ),
            // This list filters on title and last-message preview and nothing
            // else, so it says so. Borrowing the in-conversation notice here
            // promised a search of this device's history that the list has
            // never performed (ADR-052).
            (_, _, true, _) => AppStatePanel.empty(
              title: strings.chatsNoSearchResultsTitle,
              message: strings.chatsListSearchScopeNotice,
            ),
            _ => ListView.builder(
              key: const PageStorageKey('chats-list'),
              itemCount: items.length + (query.isEmpty ? 0 : 1),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Text(
                      strings.chatsListSearchScopeNotice,
                      textAlign: TextAlign.center,
                      style: context.tokens.typography.label.copyWith(
                        color: context.tokens.colors.textMuted,
                      ),
                    ),
                  );
                }
                final item = items[index];
                return _ConversationRow(
                  item: item,
                  onTap: () => _open(item),
                  onAction: (action) =>
                      _handleConversationAction(item, action, ref),
                );
              },
            ),
          },
        ),
      ],
    );
    if (widget.compact) return body;
    return Scaffold(
      key: const ValueKey('chats-list-screen'),
      appBar: AppBar(
        title: Text(strings.chatsTitle),
        actions: [
          AppIconButton(
            icon: AppIcons.search,
            semanticLabel: strings.chatsSearchAction,
            onPressed: _searchFocus.requestFocus,
            kind: AppButtonKind.ghost,
          ),
        ],
      ),
      body: body,
    );
  }

  void _open(ChatListItemViewModel item) {
    final callback = widget.onOpenConversation;
    if (callback != null) {
      callback(item);
      return;
    }
    if (item.savedMessages) {
      context.go('/saved-messages?conversationId=${item.conversationId}');
    } else if (item.group) {
      context.go('/groups/${item.conversationId}');
    } else {
      context.go(
        '/chats/conversation/${item.conversationId}'
        '?peer=${item.peerUserId ?? ''}',
      );
    }
  }

  Future<void> _handleConversationAction(
    ChatListItemViewModel item,
    _ConversationAction action,
    WidgetRef? ref,
  ) async {
    if (ref == null) return;
    final strings = AppLocalizations.of(context);
    final manager = await ref.read(manageLocalConversationStateProvider.future);
    switch (action) {
      case _ConversationAction.mute:
        await manager.mute(
          conversationId: item.conversationId,
          until: item.muted
              ? null
              : DateTime.now().toUtc().add(const Duration(hours: 8)),
        );
      case _ConversationAction.markRead:
        await manager.markRead(item.conversationId);
      case _ConversationAction.markUnread:
        final currentUserId = ref.read(authenticationControllerProvider).userId;
        if (currentUserId != null) {
          await manager.markUnread(
            conversationId: item.conversationId,
            currentUserId: currentUserId,
          );
        }
      case _ConversationAction.pin:
        await manager.setPinned(
          conversationId: item.conversationId,
          pinned: !item.pinned,
        );
      case _ConversationAction.delete:
        if (!mounted) return;
        await showAppDialog<void>(
          context: context,
          title: strings.chatsDeleteTitle,
          body: strings.chatsDeleteLocalOnlyMessage,
          actions: [
            AppButton(
              label: strings.chatCancelAction,
              kind: AppButtonKind.ghost,
              onPressed: () => popAppModal(context),
            ),
            AppButton(
              label: strings.chatDeleteForMeAction,
              kind: AppButtonKind.danger,
              onPressed: () {
                popAppModal(context);
                unawaited(manager.deleteConversationForMe(item.conversationId));
              },
            ),
          ],
        );
    }
  }
}

class DirectChatPage extends ConsumerWidget {
  const DirectChatPage({
    required this.peerUserId,
    this.conversationId,
    this.injectedModel,
    this.onIntent,
    super.key,
  });

  final String peerUserId;
  final String? conversationId;
  final ChatTimelineViewModel? injectedModel;
  final ChatIntentCallback? onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ConversationBoundary(
    peerUserId: peerUserId,
    conversationId: conversationId,
    savedMessages: false,
    injectedModel: injectedModel,
    onIntent: onIntent,
  );
}

class SavedMessagesPage extends ConsumerWidget {
  const SavedMessagesPage({
    this.conversationId,
    this.injectedModel,
    this.onIntent,
    super.key,
  });

  final String? conversationId;
  final ChatTimelineViewModel? injectedModel;
  final ChatIntentCallback? onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ConversationBoundary(
    conversationId: conversationId,
    savedMessages: true,
    injectedModel: injectedModel,
    onIntent: onIntent,
  );
}

class _ConversationBoundary extends ConsumerWidget {
  const _ConversationBoundary({
    required this.savedMessages,
    this.peerUserId,
    this.conversationId,
    this.injectedModel,
    this.onIntent,
  });

  final bool savedMessages;
  final String? peerUserId;
  final String? conversationId;
  final ChatTimelineViewModel? injectedModel;
  final ChatIntentCallback? onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (injectedModel case final model?) {
      return ChatConversationView(
        model: model,
        onIntent: onIntent ?? (_) {},
        peerUserId: peerUserId,
      );
    }
    final auth = ref.watch(authenticationControllerProvider);
    final currentUserId = auth.userId;
    if (currentUserId == null) {
      return _ConversationFailurePage(savedMessages: savedMessages);
    }
    final identity = conversationId == null
        ? ref.watch(
            conversationIdentityProvider((
              currentUserId: currentUserId,
              peerUserId: peerUserId,
              savedMessages: savedMessages,
            )),
          )
        : AsyncValue.data(conversationId!);
    return identity.when(
      data: (id) => _ProjectedConversationPage(
        currentUserId: currentUserId,
        conversationId: id,
        peerUserId: peerUserId,
        savedMessages: savedMessages,
        offline: auth.access == AuthenticationRouteAccess.offlineFullScope,
      ),
      loading: () => _ConversationLoadingPage(savedMessages: savedMessages),
      error: (_, _) => _ConversationFailurePage(savedMessages: savedMessages),
    );
  }
}

class _ProjectedConversationPage extends ConsumerWidget {
  const _ProjectedConversationPage({
    required this.currentUserId,
    required this.conversationId,
    required this.peerUserId,
    required this.savedMessages,
    required this.offline,
  });

  final String currentUserId;
  final String conversationId;
  final String? peerUserId;
  final bool savedMessages;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final contact = peerUserId == null
        ? const AsyncValue<ContactProjection?>.data(null)
        : ref.watch(contactProvider(peerUserId!));
    final peerName =
        contact.value?.presentationName ??
        (peerUserId == null
            ? strings.savedMessagesTitle
            : _shortIdentity(peerUserId!));
    final messages = ref.watch(
      conversationMessagesProvider((
        currentUserId: currentUserId,
        conversationId: conversationId,
      )),
    );
    final summaries =
        ref.watch(conversationSummariesProvider(currentUserId)).value ??
        const <ConversationSummary>[];
    final summary = summaries
        .where((item) => item.conversationId == conversationId)
        .firstOrNull;
    final forwardTargets = ChatViewModelMapper.summaries(
      summaries,
      now: DateTime.now(),
      savedMessagesTitle: strings.savedMessagesTitle,
      peerTitle: _shortIdentity,
    ).where((item) => item.conversationId != conversationId).toList();
    if (!savedMessages &&
        !forwardTargets.any((target) => target.savedMessages)) {
      forwardTargets.insert(
        0,
        ChatListItemViewModel(
          conversationId: '',
          title: strings.savedMessagesTitle,
          preview: '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          unreadCount: 0,
          muted: false,
          pinned: false,
          savedMessages: true,
          peerUserId: null,
        ),
      );
    }
    final typing =
        ref.watch(typingProjectionsProvider(conversationId)).value ??
        const <TypingProjection>[];
    // One gate for every load state. The projection is only allowed to speak
    // about trust once it has an answer to give: a first read that is still in
    // flight has neither a value nor an error, and reading that as "unverified"
    // opened every conversation on a security warning that cleared itself.
    // An error resolves closed, through the null branch of the mapper.
    final securityGate = savedMessages
        ? ChatSecurityGate.ready
        : ChatViewModelMapper.securityGate(
            contact.value?.trustState,
            resolved: contact.hasValue || contact.hasError,
          );
    final model = messages.when(
      data: (timeline) => ChatTimelineViewModel(
        state: timeline.page.messages.isEmpty
            ? ChatTimelineLoadState.empty
            : ChatTimelineLoadState.data,
        conversationId: conversationId,
        title: savedMessages ? strings.savedMessagesTitle : peerName,
        savedMessages: savedMessages,
        securityGate: securityGate,
        offline: offline,
        hasMoreBefore: timeline.page.hasMoreBefore,
        loadingBefore: timeline.loadingBefore,
        olderLoadFailed: timeline.olderLoadFailed,
        typing: typing.isNotEmpty,
        pinnedMessages: ChatViewModelMapper.messages(
          timeline.page.pinned,
          currentUserId: currentUserId,
          currentUserName: strings.chatYouAuthor,
          peerName: peerName,
        ),
        messages: ChatViewModelMapper.messages(
          timeline.page.messages,
          currentUserId: currentUserId,
          currentUserName: strings.chatYouAuthor,
          peerName: peerName,
        ),
      ),
      loading: () => ChatTimelineViewModel(
        state: ChatTimelineLoadState.loading,
        conversationId: conversationId,
        title: savedMessages ? strings.savedMessagesTitle : peerName,
        savedMessages: savedMessages,
        securityGate: securityGate,
        offline: offline,
        hasMoreBefore: false,
        loadingBefore: false,
        olderLoadFailed: false,
        typing: false,
        pinnedMessages: const [],
        messages: const [],
      ),
      error: (_, _) => ChatTimelineViewModel(
        state: ChatTimelineLoadState.error,
        conversationId: conversationId,
        title: savedMessages ? strings.savedMessagesTitle : peerName,
        savedMessages: savedMessages,
        securityGate: securityGate,
        offline: offline,
        hasMoreBefore: false,
        loadingBefore: false,
        olderLoadFailed: false,
        typing: false,
        pinnedMessages: const [],
        messages: const [],
        errorCode: 'local_history_unavailable',
      ),
    );
    // Registering visibility here rather than inside the view keeps it tied to
    // the route that actually resolved a conversation identity, and to the
    // identity it resolved. A message arriving into the conversation on screen
    // has already made the user aware of itself; the alert path reads this so
    // it does not announce what they are looking at.
    return VisibleConversationScope(
      registry: ref.watch(visibleConversationProvider),
      conversationId: conversationId,
      child: ChatConversationView(
        model: model,
        peerUserId: peerUserId,
        initialDraft: summary?.draft,
        forwardTargets: forwardTargets,
        onIntent: (intent) => _dispatch(
          context,
          ref,
          intent,
          model: model,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  Future<void> _dispatch(
    BuildContext context,
    WidgetRef ref,
    ChatIntent intent, {
    required ChatTimelineViewModel model,
    required String currentUserId,
  }) async {
    if (intent case CopyMessageIntent(:final text)) {
      await Clipboard.setData(ClipboardData(text: text));
      return;
    }
    if (intent case SaveDraftIntent(:final text)) {
      final manager = await ref.read(
        manageLocalConversationStateProvider.future,
      );
      await manager.saveDraft(conversationId: conversationId, text: text);
      return;
    }
    if (intent is ClearConversationHistoryIntent) {
      final manager = await ref.read(
        manageLocalConversationStateProvider.future,
      );
      await manager.deleteConversationForMe(conversationId);
      return;
    }
    if (intent case OpenAttachmentIntent(:final attachment)) {
      if (context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => AttachmentSheet(descriptor: attachment),
        );
      }
      return;
    }
    if (intent is LoadOlderMessagesIntent) {
      final window = await ref.read(
        conversationTimelineWindowProvider((
          currentUserId: currentUserId,
          conversationId: conversationId,
        )).future,
      );
      await window.loadOlder();
      return;
    }
    if (intent case JumpToMessageIntent(:final messageId)) {
      // A jump can name a message older than anything loaded — a search hit, a
      // reply quote, or the oldest pin in the thread. The window opens far
      // enough back to contain it, and the timeline jumps when it arrives.
      final window = await ref.read(
        conversationTimelineWindowProvider((
          currentUserId: currentUserId,
          conversationId: conversationId,
        )).future,
      );
      await window.reveal(messageId);
      return;
    }
    if (intent is ReplyToMessageIntent ||
        intent is BeginEditMessageIntent ||
        intent is ForwardMessageIntent) {
      return;
    }
    final deviceId = await ref.read(currentMessagingDeviceIdProvider.future);
    if (!context.mounted) return;
    final sender = await ref.read(
      sendConversationEventsProvider((
        userId: currentUserId,
        deviceId: deviceId,
      )).future,
    );
    Result<void>? result;
    switch (intent) {
      case SendTextIntent(
        :final text,
        :final replyToMessageId,
        :final quoteFallback,
      ):
        final sent = await sender.sendText(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          target: savedMessages
              ? const SavedConversationTarget()
              : DirectConversationTarget(peerUserId!),
          text: text,
          replyToMessageId: replyToMessageId,
          quoteFallback: quoteFallback,
        );
        result = sent.fold(
          onSuccess: (_) => const Result.success(null),
          onFailure: Result.failure,
        );
      case EditMessageIntent(:final messageId, :final text):
        result = await sender.editMessage(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          conversationId: conversationId,
          messageId: messageId,
          replacementText: text,
        );
      case SetReactionIntent(:final messageId, :final emoji):
        result = await sender.setReaction(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          conversationId: conversationId,
          messageId: messageId,
          emoji: emoji,
        );
      case SetPinIntent(:final messageId, :final pinned):
        result = await sender.setPin(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          conversationId: conversationId,
          messageId: messageId,
          pinned: pinned,
        );
      case DeleteForMeIntent(:final messageId):
        final manager = await ref.read(
          manageLocalConversationStateProvider.future,
        );
        result = await manager.deleteForMe(messageId);
      case SetStarIntent(:final messageId, :final starred):
        final manager = await ref.read(
          manageLocalConversationStateProvider.future,
        );
        result = await manager.setStar(messageId: messageId, starred: starred);
      case DeleteForEveryoneIntent(:final messageId):
        result = await sender.deleteForEveryone(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          conversationId: conversationId,
          messageId: messageId,
        );
      case RetryMessageIntent(:final message):
        result = await sender.retrySend(
          currentUserId: currentUserId,
          currentDeviceId: deviceId,
          target: savedMessages
              ? const SavedConversationTarget()
              : DirectConversationTarget(peerUserId!),
          messageId: message.id,
          text: message.text ?? '',
          replyToMessageId: message.replyToMessageId,
          quoteFallback: message.replyQuote,
        );
      case ForwardToConversationsIntent(:final message, :final targets):
        if (message.text == null || message.text!.trim().isEmpty) {
          result = const Result.failure(
            ValidationFailure(ValidationFailureKind.invalidInput),
          );
          break;
        }
        for (final target in targets) {
          final sent = await sender.sendText(
            currentUserId: currentUserId,
            currentDeviceId: deviceId,
            target: target.savedMessages
                ? const SavedConversationTarget()
                : DirectConversationTarget(target.peerUserId!),
            text: message.text!,
            quoteFallback: message.replyQuote,
          );
          if (sent case FailureResult(failure: final failure)) {
            result = Result.failure(failure);
            break;
          }
        }
        result ??= const Result.success(null);
      case MarkConversationReadIntent():
        final manager = await ref.read(
          manageLocalConversationStateProvider.future,
        );
        result = (await manager.markRead(conversationId)).fold(
          onSuccess: (_) => const Result.success(null),
          onFailure: Result.failure,
        );
      default:
        break;
    }
    if (result case FailureResult()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).chatActionFailedMessage),
          ),
        );
      }
    }
  }
}

class ChatConversationView extends StatefulWidget {
  const ChatConversationView({
    required this.model,
    required this.onIntent,
    this.peerUserId,
    this.initialDraft,
    this.forwardTargets = const [],
    super.key,
  });

  final ChatTimelineViewModel model;
  final ChatIntentCallback onIntent;
  final String? peerUserId;
  final String? initialDraft;
  final List<ChatListItemViewModel> forwardTargets;

  @override
  State<ChatConversationView> createState() => _ChatConversationViewState();
}

class _ChatConversationViewState extends State<ChatConversationView> {
  final GlobalKey<ChatComposerBuilderState> _composerKey = GlobalKey();
  String? _highlightedMessageId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onIntent(const MarkConversationReadIntent());
    });
  }

  void _handleIntent(ChatIntent intent) {
    if (intent is ReplyToMessageIntent || intent is BeginEditMessageIntent) {
      _composerKey.currentState?.handleIntent(intent);
    }
    if (intent case JumpToMessageIntent(:final messageId)) {
      setState(() => _highlightedMessageId = messageId);
    }
    if (intent case ForwardMessageIntent(:final message)) {
      unawaited(_showForwardPicker(message));
      return;
    }
    widget.onIntent(intent);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final model = ChatTimelineViewModel(
      state: widget.model.state,
      conversationId: widget.model.conversationId,
      title: widget.model.title,
      savedMessages: widget.model.savedMessages,
      securityGate: widget.model.securityGate,
      offline: widget.model.offline,
      hasMoreBefore: widget.model.hasMoreBefore,
      loadingBefore: widget.model.loadingBefore,
      olderLoadFailed: widget.model.olderLoadFailed,
      typing: widget.model.typing,
      pinnedMessages: widget.model.pinnedMessages,
      messages: widget.model.messages,
      errorCode: widget.model.errorCode,
      highlightedMessageId:
          _highlightedMessageId ?? widget.model.highlightedMessageId,
    );
    return RepaintBoundary(
      key: const ValueKey('chat-interface-golden'),
      child: Scaffold(
        key: ValueKey(
          widget.model.savedMessages
              ? 'saved-messages-screen'
              : 'direct-chat-screen',
        ),
        appBar: AppBar(
          leading: AppIconButton(
            icon: AppIcons.back,
            semanticLabel: strings.authBackAction,
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/chats'),
            kind: AppButtonKind.ghost,
          ),
          titleSpacing: 0,
          title: Semantics(
            button: !widget.model.savedMessages,
            label: widget.model.title,
            child: InkWell(
              onTap: widget.model.savedMessages || widget.peerUserId == null
                  ? null
                  : () => context.push('/contacts/${widget.peerUserId}'),
              child: Row(
                children: [
                  if (widget.model.savedMessages)
                    CircleAvatar(
                      backgroundColor: context.tokens.colors.accentSoft,
                      foregroundColor: context.tokens.colors.accent,
                      child: const AppIcon(AppIcons.saved),
                    )
                  else
                    ContactAvatar(
                      username: widget.model.title,
                      semanticLabel: widget.model.title,
                      radius: 20,
                    ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.model.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Only while somebody is actually typing.
                        //
                        // This line used to fall through to a presence claim,
                        // and the claim was structurally false: no part of this
                        // client ever sends `subscribe_presence`, so the server
                        // has no target to emit presence to and every peer read
                        // as offline forever — including one holding a live
                        // socket in the same room. Saying nothing is the honest
                        // state until the subscription exists.
                        if (!widget.model.savedMessages && widget.model.typing)
                          Text(
                            strings.chatTypingStatus,
                            style: context.tokens.typography.label.copyWith(
                              color: context.tokens.colors.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppIconButton(
              icon: AppIcons.search,
              semanticLabel: strings.chatSearchAction,
              onPressed: _showSearch,
              kind: AppButtonKind.ghost,
            ),
            AppIconButton(
              icon: AppIcons.more,
              semanticLabel: strings.chatMoreAction,
              onPressed: _showConversationMenu,
              kind: AppButtonKind.ghost,
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.model.pinnedMessages.isNotEmpty)
              _PinnedBanner(
                count: widget.model.pinnedMessages.length,
                onJump: () => _handleIntent(
                  JumpToMessageIntent(widget.model.pinnedMessages.first.id),
                ),
                onExpand: _showPinnedMessages,
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppContentWidths.readable,
                  ),
                  child: ChatTimelineAdapter(
                    model: model,
                    onIntent: _handleIntent,
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppContentWidths.readable,
                ),
                child: ChatComposerBuilder(
                  key: _composerKey,
                  securityGate: widget.model.securityGate,
                  offline: widget.model.offline,
                  savedMessages: widget.model.savedMessages,
                  initialDraft: widget.initialDraft,
                  onIntent: _handleIntent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSearch() => showConversationSearch(
    context: context,
    messages: widget.model.messages,
    onJumpToMessage: (id) => _handleIntent(JumpToMessageIntent(id)),
  );

  Future<void> _showPinnedMessages() async {
    final strings = AppLocalizations.of(context);
    final pinned = widget.model.pinnedMessages;
    await showAppSheet<void>(
      context: context,
      semanticLabel: strings.chatPinnedMessagesTitle,
      child: SizedBox(
        height: mathMin(MediaQuery.sizeOf(context).height * .65, 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.chatPinnedMessagesTitle,
              style: context.tokens.typography.section,
            ),
            const SizedBox(height: AppSpacing.x3),
            Expanded(
              child: ListView.builder(
                itemCount: pinned.length,
                itemBuilder: (context, index) {
                  final message = pinned[index];
                  return ListTile(
                    leading: const AppIcon(AppIcons.pin),
                    title: Text(
                      message.text ?? strings.chatDeletedMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: TextButton(
                      onPressed: () => _handleIntent(
                        SetPinIntent(messageId: message.id, pinned: false),
                      ),
                      child: Text(strings.chatUnpinAction),
                    ),
                    onTap: () {
                      popAppModal(context);
                      _handleIntent(JumpToMessageIntent(message.id));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showForwardPicker(ChatMessageViewModel message) async {
    final strings = AppLocalizations.of(context);
    final selected = <String>{};
    await showAppSheet<void>(
      context: context,
      semanticLabel: strings.chatForwardAction,
      child: StatefulBuilder(
        builder: (context, setModalState) => SizedBox(
          height: mathMin(MediaQuery.sizeOf(context).height * .7, 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.chatForwardAction,
                style: context.tokens.typography.section,
              ),
              const SizedBox(height: AppSpacing.x2),
              Expanded(
                child: widget.forwardTargets.isEmpty
                    ? AppStatePanel.empty(
                        title: strings.chatsEmptyTitle,
                        message: strings.chatsEmptyMessage,
                      )
                    : ListView.builder(
                        itemCount: widget.forwardTargets.length,
                        itemBuilder: (context, index) {
                          final target = widget.forwardTargets[index];
                          final selectionKey = target.savedMessages
                              ? 'saved'
                              : target.conversationId;
                          return CheckboxListTile(
                            value: selected.contains(selectionKey),
                            title: Text(target.title),
                            secondary: target.savedMessages
                                ? const AppIcon(AppIcons.saved)
                                : ContactAvatar(
                                    username: target.title,
                                    semanticLabel: target.title,
                                    radius: 18,
                                  ),
                            onChanged: (value) {
                              setModalState(() {
                                if (value ?? false) {
                                  selected.add(selectionKey);
                                } else {
                                  selected.remove(selectionKey);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
              AppButton(
                label: strings.chatForwardAction,
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        final targets = widget.forwardTargets.where((target) {
                          final key = target.savedMessages
                              ? 'saved'
                              : target.conversationId;
                          return selected.contains(key);
                        });
                        popAppModal(context);
                        widget.onIntent(
                          ForwardToConversationsIntent(
                            message: message,
                            targets: targets,
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Clearing is local, and the dialog says so.
  ///
  /// It removes this device's copy of the conversation and nothing else:
  /// the peer keeps theirs, this account's other devices keep theirs, and no
  /// request is sent asking anybody to forget anything. Wording that implied
  /// otherwise would be the promise §17 forbids a destructive dialog from
  /// making.
  Future<void> _confirmClearHistory() async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: strings.chatClearHistoryTitle,
      body: strings.chatClearHistoryBody,
      actions: [
        AppButton(
          label: strings.chatCancelAction,
          kind: AppButtonKind.ghost,
          onPressed: () => popAppModal<bool>(context, false),
        ),
        AppButton(
          key: const ValueKey('chat-clear-history-confirm'),
          label: strings.chatClearHistoryAction,
          kind: AppButtonKind.danger,
          onPressed: () => popAppModal<bool>(context, true),
        ),
      ],
    );
    if (confirmed ?? false) {
      _handleIntent(const ClearConversationHistoryIntent());
    }
  }

  Future<void> _showConversationMenu() async {
    final strings = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      semanticLabel: strings.chatMoreAction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.model.savedMessages)
            _MenuRow(
              label: strings.contactVerifyAction,
              icon: AppIcons.security,
              onTap: () {
                popAppModal(context);
                if (widget.peerUserId != null) {
                  unawaited(
                    context.push('/contacts/${widget.peerUserId}/safety'),
                  );
                }
              },
            ),
          _MenuRow(
            label: strings.chatPinnedMessagesTitle,
            icon: AppIcons.pin,
            onTap: () {
              popAppModal(context);
              unawaited(_showPinnedMessages());
            },
          ),
          _MenuRow(
            label: strings.contactClearHistoryAction,
            icon: AppIcons.delete,
            danger: true,
            onTap: () {
              popAppModal(context);
              unawaited(_confirmClearHistory());
            },
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.item,
    required this.onTap,
    required this.onAction,
  });

  final ChatListItemViewModel item;
  final VoidCallback onTap;
  final ValueChanged<_ConversationAction> onAction;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final semanticLabel = strings.chatsItemSemantics(
      item.title,
      item.preview,
      item.unreadCount,
    );
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showMenu(context),
        onSecondaryTapUp: (_) => _showMenu(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x2,
            ),
            child: Row(
              children: [
                if (item.savedMessages)
                  CircleAvatar(
                    backgroundColor: context.tokens.colors.accentSoft,
                    child: const AppIcon(AppIcons.saved),
                  )
                else
                  ContactAvatar(
                    username: item.title,
                    semanticLabel: item.title,
                  ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tokens.typography.body.copyWith(
                                fontWeight: item.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          Text(
                            MaterialLocalizations.of(context).formatTimeOfDay(
                              TimeOfDay.fromDateTime(item.timestamp),
                            ),
                            style: context.tokens.typography.label.copyWith(
                              color: context.tokens.colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.preview.isEmpty
                                  ? strings.chatsNoMessagesPreview
                                  : item.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.tokens.typography.compact.copyWith(
                                color: context.tokens.colors.textMuted,
                              ),
                            ),
                          ),
                          if (item.muted)
                            AppIcon(
                              AppIcons.muted,
                              color: context.tokens.colors.textMuted,
                              size: 16,
                            ),
                          if (item.pinned)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: AppSpacing.x1,
                              ),
                              child: AppIcon(
                                AppIcons.pin,
                                color: context.tokens.colors.textMuted,
                                size: 16,
                              ),
                            ),
                          if (item.unreadCount > 0)
                            Container(
                              margin: const EdgeInsetsDirectional.only(
                                start: AppSpacing.x2,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x1,
                              ),
                              decoration: BoxDecoration(
                                color: context.tokens.colors.accent,
                                borderRadius: AppRadii.pill,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${item.unreadCount}',
                                style: context.tokens.typography.label.copyWith(
                                  color: context.tokens.colors.canvas,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      semanticLabel: strings.chatsConversationActionsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuRow(
            label: item.pinned
                ? strings.chatUnpinAction
                : strings.chatPinAction,
            icon: AppIcons.pin,
            onTap: () {
              popAppModal(context);
              onAction(_ConversationAction.pin);
            },
          ),
          _MenuRow(
            label: item.muted
                ? strings.chatsUnmuteAction
                : strings.chatsMuteAction,
            icon: AppIcons.muted,
            onTap: () {
              popAppModal(context);
              onAction(_ConversationAction.mute);
            },
          ),
          if (!item.savedMessages)
            _MenuRow(
              label: item.unreadCount > 0
                  ? strings.chatsMarkReadAction
                  : strings.chatsMarkUnreadAction,
              icon: AppIcons.delivered,
              onTap: () {
                popAppModal(context);
                onAction(
                  item.unreadCount > 0
                      ? _ConversationAction.markRead
                      : _ConversationAction.markUnread,
                );
              },
            ),
          _MenuRow(
            label: strings.chatsDeleteAction,
            icon: AppIcons.delete,
            danger: true,
            onTap: () {
              popAppModal(context);
              onAction(_ConversationAction.delete);
            },
          ),
        ],
      ),
    );
  }
}

enum _ConversationAction { pin, mute, markRead, markUnread, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: AppFocus.minimumTarget,
    leading: AppIcon(
      icon,
      color: danger
          ? context.tokens.colors.danger
          : context.tokens.colors.textPrimary,
    ),
    title: Text(
      label,
      style: context.tokens.typography.body.copyWith(
        color: danger
            ? context.tokens.colors.danger
            : context.tokens.colors.textPrimary,
      ),
    ),
    onTap: onTap,
  );
}

class _PinnedBanner extends StatelessWidget {
  const _PinnedBanner({
    required this.count,
    required this.onJump,
    required this.onExpand,
  });

  final int count;
  final VoidCallback onJump;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final label = strings.chatPinnedBanner(count);
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Material(
        color: context.tokens.colors.accentSoft,
        child: InkWell(
          onTap: onJump,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x3,
              vertical: AppSpacing.x2,
            ),
            child: Row(
              children: [
                AppIcon(AppIcons.pin, color: context.tokens.colors.accent),
                const SizedBox(width: AppSpacing.x2),
                Expanded(
                  child: Text(
                    label,
                    style: context.tokens.typography.compact.copyWith(
                      color: context.tokens.colors.accent,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onExpand,
                  child: Text(strings.chatPinnedExpandAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.label, required this.kind, super.key});

  final String label;
  final AppStatusKind kind;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.x2),
    child: AppStatusBadge(kind: kind, label: label),
  );
}

class _ConversationLoadingPage extends StatelessWidget {
  const _ConversationLoadingPage({required this.savedMessages});

  final bool savedMessages;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        savedMessages
            ? AppLocalizations.of(context).savedMessagesTitle
            : AppLocalizations.of(context).chatTitle,
      ),
    ),
    body: AppStatePanel.loading(
      title: AppLocalizations.of(context).chatHistoryLoading,
    ),
  );
}

class _ConversationFailurePage extends StatelessWidget {
  const _ConversationFailurePage({required this.savedMessages});

  final bool savedMessages;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        savedMessages
            ? AppLocalizations.of(context).savedMessagesTitle
            : AppLocalizations.of(context).chatTitle,
      ),
    ),
    body: AppStatePanel.error(
      title: AppLocalizations.of(context).chatHistoryErrorTitle,
      message: AppLocalizations.of(context).chatHistoryErrorMessage,
    ),
  );
}

double mathMin(double left, double right) => left < right ? left : right;

/// Reduces the engine's connection phase to the four states a screen may show.
///
/// The phases this collapses are not equally interesting to a person. Every
/// terminal one — revoked, circuit open, origin rejected — is a condition the
/// session-level surfaces already own and speak about properly, so this reports
/// them as waiting rather than inventing a second, vaguer voice for them here.
ChatDeliveryIndicator _deliveryIndicator(SyncConnectionPhase? phase) =>
    switch (phase) {
      null || SyncConnectionPhase.online => ChatDeliveryIndicator.settled,
      SyncConnectionPhase.connecting => ChatDeliveryIndicator.connecting,
      SyncConnectionPhase.draining => ChatDeliveryIndicator.syncing,
      SyncConnectionPhase.stopped ||
      SyncConnectionPhase.offline ||
      SyncConnectionPhase.reconnectWaiting ||
      SyncConnectionPhase.revoked ||
      SyncConnectionPhase.protocolCircuitOpen ||
      SyncConnectionPhase.originRejected => ChatDeliveryIndicator.waiting,
    };

/// The line for a delivery state, or nothing at all when there is nothing to
/// say.
///
/// A settled session renders no notice. An indicator that is always on screen
/// is one nobody reads, and this one exists precisely to be noticed on the day
/// it stops changing.
String? _deliveryNotice(
  ChatDeliveryIndicator indicator,
  AppLocalizations strings,
) => switch (indicator) {
  ChatDeliveryIndicator.settled => null,
  ChatDeliveryIndicator.connecting => strings.chatsDeliveryConnectingNotice,
  ChatDeliveryIndicator.syncing => strings.chatsDeliverySyncingNotice,
  ChatDeliveryIndicator.waiting => strings.chatsDeliveryWaitingNotice,
};

String _shortIdentity(String value) =>
    value.length <= 12 ? value : '${value.substring(0, 8)}…';
