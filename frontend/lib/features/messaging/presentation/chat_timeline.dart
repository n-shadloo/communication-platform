import 'dart:async';
import 'dart:math' as math;

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_emoji_picker.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

typedef ChatIntentCallback = void Function(ChatIntent intent);

/// The reactions the floating selector offers, in this order.
///
/// Presentation only, and deliberately so: `message-protocol.md` carries "one
/// normalized emoji grapheme or null", every layer below this one takes whatever
/// grapheme it is handed, and nothing outside this file knows which twenty-four
/// are on the panel. Each entry is one grapheme cluster - `❤️` and `🕊️` are a
/// base plus U+FE0F, the rest are single scalars - which is what
/// `SendConversationEvents.setReaction` requires before it will encode one.
const chatQuickReactions = <String>[
  '👍',
  '👎',
  '❤️',
  '🔥',
  '🥰',
  '👏',
  '😁',
  '🤔',
  '🤯',
  '😱',
  '🤬',
  '😢',
  '🎉',
  '🤩',
  '🤮',
  '💩',
  '🙏',
  '👌',
  '🕊️',
  '🤡',
  '🥱',
  '😍',
  '🐳',
  '💯',
];

/// The one reaction a double tap sets, and the one it removes when it is
/// already this user's. It is the first entry of [chatQuickReactions] and has to
/// stay in that list, because the selector marks the active reaction as selected
/// and a double tap must be undoable from the panel as well.
const chatDoubleTapReaction = '👍';

/// Replaceable timeline boundary.
///
/// This adapter deliberately uses a custom reversed sliver surface rather than keeping
/// messages in a Flyer controller. Reversed stable indices make upward pagination an
/// append at the far edge, preserving the current reading anchor. Every builder below
/// receives only immutable application view models and emits typed intents.
class ChatTimelineAdapter extends StatefulWidget {
  const ChatTimelineAdapter({
    required this.model,
    required this.onIntent,
    this.initialPageSize = 80,
    this.pageSize = 60,
    super.key,
  });

  final ChatTimelineViewModel model;
  final ChatIntentCallback onIntent;
  final int initialPageSize;
  final int pageSize;

  @override
  State<ChatTimelineAdapter> createState() => _ChatTimelineAdapterState();
}

class _ChatTimelineAdapterState extends State<ChatTimelineAdapter> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _distanceFromBottom = ValueNotifier(0);
  final Map<String, GlobalKey> _messageKeys = {};
  var _visibleMessageCount = 0;
  var _loadRequestSent = false;
  _ReadingAnchor? _pendingAnchor;
  _ReadingAnchor? _lastReadingAnchor;
  var _anchorSnapshotScheduled = false;
  var _dependenciesInitialized = false;

  @override
  void initState() {
    super.initState();
    _visibleMessageCount = math.min(
      widget.initialPageSize,
      widget.model.messages.length,
    );
    _scrollController.addListener(_onScroll);
    _scrollController.addListener(_updateDistanceFromBottom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpIfRequested(widget.model.highlightedMessageId, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ChatTimelineAdapter oldWidget) {
    _pendingAnchor = _captureReadingAnchor();
    super.didUpdateWidget(oldWidget);
    final delta =
        widget.model.messages.length - oldWidget.model.messages.length;
    if (delta > 0 && _visibleMessageCount >= oldWidget.model.messages.length) {
      _visibleMessageCount = math.min(
        widget.model.messages.length,
        _visibleMessageCount + delta,
      );
    }
    if (!widget.model.loadingBefore) {
      _loadRequestSent = false;
    }
    if (widget.model.highlightedMessageId !=
        oldWidget.model.highlightedMessageId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfRequested(widget.model.highlightedMessageId);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreReadingAnchor();
      });
    }
  }

  @override
  void didChangeDependencies() {
    if (_dependenciesInitialized) {
      _pendingAnchor = _captureReadingAnchor();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreReadingAnchor();
      });
    }
    _dependenciesInitialized = true;
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..removeListener(_updateDistanceFromBottom)
      ..dispose();
    _distanceFromBottom.dispose();
    super.dispose();
  }

  void _updateDistanceFromBottom() {
    if (_scrollController.hasClients) {
      _distanceFromBottom.value = _scrollController.position.pixels;
      _scheduleAnchorSnapshot();
    }
  }

  void _scheduleAnchorSnapshot() {
    if (_anchorSnapshotScheduled) return;
    _anchorSnapshotScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorSnapshotScheduled = false;
      if (mounted) {
        _lastReadingAnchor = _captureReadingAnchor();
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadOlder();
    }
  }

  void _loadOlder() {
    if (_visibleMessageCount < widget.model.messages.length) {
      _pendingAnchor = _captureReadingAnchor();
      setState(() {
        _visibleMessageCount = math.min(
          widget.model.messages.length,
          _visibleMessageCount + widget.pageSize,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreReadingAnchor();
      });
      return;
    }
    if (widget.model.hasMoreBefore &&
        !widget.model.loadingBefore &&
        !_loadRequestSent) {
      _loadRequestSent = true;
      widget.onIntent(const LoadOlderMessagesIntent());
    }
  }

  _ReadingAnchor? _captureReadingAnchor() {
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels <= 1) {
      return null;
    }
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    _ReadingAnchor? best;
    for (final entry in _messageKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final top = render.localToGlobal(Offset.zero).dy;
      final bottom = top + render.size.height;
      if (bottom <= viewportTop || top >= viewportBottom) continue;
      if (best == null || top < best.globalTop) {
        best = _ReadingAnchor(entry.key, top);
      }
    }
    return best;
  }

  void _restoreReadingAnchor() {
    final anchor = _pendingAnchor;
    _pendingAnchor = null;
    if (anchor == null || !_scrollController.hasClients) return;
    final render = _messageKeys[anchor.messageId]?.currentContext
        ?.findRenderObject();
    if (render is! RenderBox || !render.attached) return;
    final newTop = render.localToGlobal(Offset.zero).dy;
    final delta = newTop - anchor.globalTop;
    if (delta.abs() < .5) return;
    final position = _scrollController.position;
    // In a reversed viewport, increasing the scroll offset moves the rendered
    // anchor in the same screen direction as a positive layout delta. Apply the
    // inverse correction so edits, reactions, media sizing, and width changes
    // leave the reader on the same visual line.
    final corrected = (position.pixels - delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    position.jumpTo(corrected);
  }

  void _jumpIfRequested(String? messageId, {bool animate = true}) {
    if (messageId == null) return;
    final sourceIndex = widget.model.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (sourceIndex < 0) return;
    final needed = widget.model.messages.length - sourceIndex;
    if (needed > _visibleMessageCount) {
      setState(() => _visibleMessageCount = needed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final reverseIndex = widget.model.messages.length - 1 - sourceIndex;
      final target = (reverseIndex * 88.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: AppMotion.route,
            curve: AppMotion.enter,
          ),
        );
      } else {
        _scrollController.jumpTo(target);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final targetContext = _messageKeys[messageId]?.currentContext;
        if (targetContext != null) {
          unawaited(
            Scrollable.ensureVisible(
              targetContext,
              alignment: 0.5,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.state,
            ),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return switch (widget.model.state) {
      ChatTimelineLoadState.loading => AppStatePanel.loading(
        title: strings.chatHistoryLoading,
      ),
      ChatTimelineLoadState.error => AppStatePanel.error(
        title: strings.chatHistoryErrorTitle,
        message: strings.chatHistoryErrorMessage,
        actionLabel: strings.retryAction,
        onAction: () => widget.onIntent(const LoadOlderMessagesIntent()),
      ),
      ChatTimelineLoadState.empty => AppStatePanel.empty(
        title: widget.model.savedMessages
            ? strings.savedMessagesEmptyTitle
            : strings.chatEmptyTitle,
        message: widget.model.savedMessages
            ? strings.savedMessagesEmptyMessage
            : strings.chatEmptyMessage,
      ),
      ChatTimelineLoadState.data => _timeline(context),
    };
  }

  Widget _timeline(BuildContext context) {
    _scheduleAnchorSnapshot();
    final start = math.max(
      0,
      widget.model.messages.length - _visibleMessageCount,
    );
    final messages = widget.model.messages.sublist(start);
    final rows = _buildRows(messages);
    final strings = AppLocalizations.of(context);
    return Stack(
      children: [
        Semantics(
          container: true,
          label: strings.chatTimelineSemantics(widget.model.title),
          explicitChildNodes: true,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _pendingAnchor ??= _lastReadingAnchor;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _restoreReadingAnchor();
                _scheduleAnchorSnapshot();
              });
              return false;
            },
            child: ListView.builder(
              key: const PageStorageKey('chat-timeline'),
              controller: _scrollController,
              reverse: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x3,
                AppSpacing.x8,
                AppSpacing.x3,
                AppSpacing.x4,
              ),
              itemCount: rows.length + 1,
              itemBuilder: (context, reverseIndex) {
                if (reverseIndex == rows.length) {
                  return _PaginationMarker(
                    hasMore: start > 0 || widget.model.hasMoreBefore,
                    loading: widget.model.loadingBefore,
                    failed: widget.model.olderLoadFailed,
                    onLoad: _loadOlder,
                  );
                }
                final row = rows[rows.length - 1 - reverseIndex];
                return switch (row) {
                  _MessageRow(:final message) => SizeChangedLayoutNotifier(
                    child: KeyedSubtree(
                      key: _messageKeys.putIfAbsent(message.id, GlobalKey.new),
                      child: ChatMessageBuilder(
                        message: message,
                        highlighted:
                            widget.model.highlightedMessageId == message.id,
                        onIntent: widget.onIntent,
                        onJumpToReply: (id) {
                          widget.onIntent(JumpToMessageIntent(id));
                          _jumpIfRequested(id);
                        },
                      ),
                    ),
                  ),
                  _DateRow(:final date) => _DateSeparator(date: date),
                  _UnreadRow() => const _UnreadDivider(),
                };
              },
            ),
          ),
        ),
        PositionedDirectional(
          end: AppSpacing.x3,
          bottom: AppSpacing.x3,
          child: ValueListenableBuilder<double>(
            valueListenable: _distanceFromBottom,
            builder: (context, distance, child) => AnimatedScale(
              duration: AppMotion.effective(context, AppMotion.state),
              scale: distance > 420 ? 1 : 0,
              child: child,
            ),
            child: AppIconButton(
              icon: AppIcons.jumpDown,
              semanticLabel: AppLocalizations.of(
                context,
              ).chatJumpToLatestAction,
              onPressed: () => _scrollController.animateTo(
                0,
                duration: AppMotion.effective(context, AppMotion.route),
                curve: AppMotion.enter,
              ),
              kind: AppButtonKind.secondary,
            ),
          ),
        ),
      ],
    );
  }

  List<_TimelineRow> _buildRows(List<ChatMessageViewModel> messages) {
    final rows = <_TimelineRow>[];
    DateTime? previousDay;
    var unreadInserted = false;
    for (final message in messages) {
      final day = DateTime(
        message.timestamp.year,
        message.timestamp.month,
        message.timestamp.day,
      );
      if (day != previousDay) {
        rows.add(_DateRow(day));
        previousDay = day;
      }
      if (!unreadInserted && message.unread) {
        rows.add(const _UnreadRow());
        unreadInserted = true;
      }
      rows.add(_MessageRow(message));
    }
    return rows;
  }
}

sealed class _TimelineRow {
  const _TimelineRow();
}

final class _MessageRow extends _TimelineRow {
  const _MessageRow(this.message);

  final ChatMessageViewModel message;
}

final class _DateRow extends _TimelineRow {
  const _DateRow(this.date);

  final DateTime date;
}

final class _UnreadRow extends _TimelineRow {
  const _UnreadRow();
}

final class _ReadingAnchor {
  const _ReadingAnchor(this.messageId, this.globalTop);

  final String messageId;
  final double globalTop;
}

class ChatMessageBuilder extends StatelessWidget {
  const ChatMessageBuilder({
    required this.message,
    required this.highlighted,
    required this.onIntent,
    required this.onJumpToReply,
    super.key,
  });

  final ChatMessageViewModel message;
  final bool highlighted;
  final ChatIntentCallback onIntent;
  final ValueChanged<String> onJumpToReply;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final strings = AppLocalizations.of(context);
    final stateLabel = _deliveryLabel(strings, message.delivery);
    final semanticLabel = strings.chatMessageSemantics(
      message.authorName,
      message.deleted
          ? strings.chatDeletedMessage
          : message.kind == ChatTimelineContentKind.unsupported
          ? strings.chatUnsupportedMessage
          : message.text ?? '',
      stateLabel,
    );
    final bubble = Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      customSemanticsActions: {
        CustomSemanticsAction(label: strings.chatReplyAction): () =>
            onIntent(ReplyToMessageIntent(message)),
        CustomSemanticsAction(label: strings.chatMessageActionsLabel): () =>
            _showActions(context),
      },
      child: FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.f10, shift: true):
              _OpenMessageMenuIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_showActions(context));
              return null;
            },
          ),
          _OpenMessageMenuIntent: CallbackAction<_OpenMessageMenuIntent>(
            onInvoke: (_) {
              unawaited(_showActions(context));
              return null;
            },
          ),
        },
        // The gap around a bubble stays outside the gesture detector, so the
        // press target is the bubble itself and not the blank column beside it.
        child: AnimatedPadding(
          duration: AppMotion.effective(context, AppMotion.state),
          curve: AppMotion.enter,
          padding: EdgeInsetsDirectional.only(
            start: message.outgoing ? AppSpacing.x12 : 0,
            end: message.outgoing ? 0 : AppSpacing.x12,
            top: message.firstInAuthorGroup ? AppSpacing.x3 : AppSpacing.x1,
            bottom: message.lastInAuthorGroup ? AppSpacing.x2 : AppSpacing.x1,
          ),
          child: GestureDetector(
            // The whole bubble is the target, not the glyphs inside it. Under
            // the default `deferToChild` a press only counts where a descendant
            // answers the hit test, so the bubble's own padding and the gaps
            // between its rows silently swallowed the press.
            //
            // `opaque` decides what happens where no descendant answers; it
            // does not take a press away from one that does. The reply quote,
            // the attachment tile, the reaction chips and the failed-send retry
            // each keep their own recognizer, and a recognizer nested inside
            // this one is entered into the gesture arena first, so it wins.
            // What they do lose is immediacy: `onDoubleTap` holds the arena for
            // `kDoubleTapTimeout` before a single tap can be awarded, and that
            // hold is per pointer rather than per detector. Telegram's model
            // costs the same.
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_showActions(context)),
            onDoubleTap: () => _toggleReaction(chatDoubleTapReaction),
            onSecondaryTapUp: (_) => unawaited(_showActions(context)),
            child: AnimatedContainer(
              key: ValueKey('message-${message.id}'),
              duration: AppMotion.effective(context, AppMotion.state),
              curve: AppMotion.enter,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x3,
                vertical: AppSpacing.x2,
              ),
              decoration: BoxDecoration(
                color: message.outgoing ? colors.accentSoft : colors.surface,
                border: Border.all(
                  color: highlighted
                      ? colors.accent
                      : message.delivery == ChatDeliveryViewState.failed
                      ? colors.danger
                      : colors.border,
                  width: highlighted ? 3 : 1,
                ),
                borderRadius: _bubbleRadius(message),
              ),
              child: _content(context),
            ),
          ),
        ),
      ),
    );
    return Align(
      alignment: message.outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor:
            AppBreakpoints.of(MediaQuery.sizeOf(context).width) ==
                AppWidthClass.narrow
            ? 0.82
            : 0.70,
        child: bubble,
      ),
    );
  }

  Widget _content(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message.firstInAuthorGroup && !message.outgoing)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.x1),
            child: Text(
              message.authorName,
              style: context.tokens.typography.label.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (message.replyQuote != null)
          InkWell(
            onTap: message.replyToMessageId == null
                ? null
                : () => onJumpToReply(message.replyToMessageId!),
            child: Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.x2),
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.x2,
                top: AppSpacing.x1,
                bottom: AppSpacing.x1,
              ),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: colors.accent, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyAuthor ?? strings.chatReplyQuote,
                    style: context.tokens.typography.label.copyWith(
                      color: colors.accent,
                    ),
                  ),
                  Text(
                    message.replyQuote!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.tokens.typography.compact,
                  ),
                ],
              ),
            ),
          ),
        switch (message.kind) {
          ChatTimelineContentKind.text => Text(
            message.deleted ? strings.chatDeletedMessage : message.text ?? '',
            textDirection: _contentDirection(message.text),
            style: context.tokens.typography.body.copyWith(
              color: message.deleted ? colors.textMuted : colors.textPrimary,
              fontStyle: message.deleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          ChatTimelineContentKind.image ||
          ChatTimelineContentKind.attachment => _AttachmentMessageContent(
            message: message,
            onOpen: () => onIntent(
              OpenAttachmentIntent(
                attachment: message.attachments.isEmpty
                    ? null
                    : message.attachments.first,
              ),
            ),
          ),
          ChatTimelineContentKind.system => _SystemMessageContent(
            text: message.text ?? strings.chatSystemMessage,
          ),
          ChatTimelineContentKind.unsupported =>
            const _UnsupportedMessageContent(),
        },
        if (message.reactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x2),
            child: Wrap(
              spacing: AppSpacing.x1,
              runSpacing: AppSpacing.x1,
              children: [
                for (final reaction in message.reactions)
                  _ReactionChip(
                    reaction: reaction,
                    onPressed: () => onIntent(
                      SetReactionIntent(
                        messageId: message.id,
                        emoji: reaction.selectedByCurrentUser
                            ? null
                            : reaction.emoji,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.x1),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.x1,
          children: [
            if (message.pinned)
              AppIcon(AppIcons.pin, color: colors.textMuted, size: 14),
            if (message.starred)
              AppIcon(AppIcons.star, color: colors.warning, size: 14),
            if (message.edited)
              Text(
                strings.chatEditedLabel,
                style: context.tokens.typography.label.copyWith(
                  color: colors.textMuted,
                ),
              ),
            if (message.timestampSkewed)
              Tooltip(
                message: strings.chatTimestampSkewed,
                child: AppIcon(
                  AppIcons.warning,
                  color: colors.warning,
                  size: 14,
                ),
              ),
            Text(
              MaterialLocalizations.of(
                context,
              ).formatTimeOfDay(TimeOfDay.fromDateTime(message.timestamp)),
              style: context.tokens.typography.label.copyWith(
                color: colors.textMuted,
              ),
            ),
            _DeliveryIndicator(state: message.delivery),
          ],
        ),
        if (message.delivery == ChatDeliveryViewState.failed)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: () => onIntent(RetryMessageIntent(message)),
              icon: AppIcon(AppIcons.retry, color: colors.danger, size: 16),
              label: Text(strings.chatRetrySendAction),
              style: TextButton.styleFrom(foregroundColor: colors.danger),
            ),
          ),
      ],
    );
  }

  /// The reaction this user has set on this message, or null.
  ///
  /// A reaction is a set operation per `(target, reacting_user)`, so at most one
  /// chip can carry `selectedByCurrentUser`.
  String? get _ownReaction {
    for (final reaction in message.reactions) {
      if (reaction.selectedByCurrentUser) {
        return reaction.emoji;
      }
    }
    return null;
  }

  /// Sets [emoji], or removes it when it is already this user's.
  ///
  /// The same rule the reaction chips have always used, reached from the
  /// selector and from the double tap so that all three agree.
  void _toggleReaction(String emoji) => onIntent(
    SetReactionIntent(
      messageId: message.id,
      emoji: _ownReaction == emoji ? null : emoji,
    ),
  );

  /// This bubble's rectangle in global coordinates, for the selector to sit
  /// above. Null when the element has no attached box - which a modal opened
  /// from a semantics action can reach - and the selector then parks itself
  /// directly above the sheet instead.
  Rect? _anchor(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _showActions(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    await showAppAnchoredSheet<void>(
      context: context,
      semanticLabel: strings.chatMessageActionsLabel,
      anchor: _anchor(context),
      anchored: _ReactionSelector(
        selected: _ownReaction,
        onSelected: (emoji) {
          popAppModal(context);
          _toggleReaction(emoji);
        },
        onExpand: () => unawaited(_expandReactions(context)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MessageAction(
                label: strings.chatReplyAction,
                icon: AppIcons.reply,
                onPressed: () {
                  popAppModal(context);
                  onIntent(ReplyToMessageIntent(message));
                },
              ),
              if (message.canEdit)
                _MessageAction(
                  label: strings.chatEditAction,
                  icon: AppIcons.edit,
                  onPressed: () {
                    popAppModal(context);
                    onIntent(BeginEditMessageIntent(message));
                  },
                ),
              if (!message.deleted && message.text?.trim().isNotEmpty == true)
                _MessageAction(
                  label: strings.chatForwardAction,
                  icon: AppIcons.forward,
                  onPressed: () {
                    popAppModal(context);
                    onIntent(ForwardMessageIntent(message));
                  },
                ),
              if (!message.deleted && message.text != null)
                _MessageAction(
                  label: strings.chatCopyAction,
                  icon: AppIcons.copy,
                  onPressed: () {
                    popAppModal(context);
                    onIntent(CopyMessageIntent(message.text!));
                  },
                ),
              _MessageAction(
                label: message.starred
                    ? strings.chatUnstarAction
                    : strings.chatStarAction,
                icon: AppIcons.star,
                onPressed: () {
                  popAppModal(context);
                  onIntent(
                    SetStarIntent(
                      messageId: message.id,
                      starred: !message.starred,
                    ),
                  );
                },
              ),
              _MessageAction(
                label: message.pinned
                    ? strings.chatUnpinAction
                    : strings.chatPinAction,
                icon: AppIcons.pin,
                onPressed: () {
                  popAppModal(context);
                  onIntent(
                    SetPinIntent(
                      messageId: message.id,
                      pinned: !message.pinned,
                    ),
                  );
                },
              ),
              _MessageAction(
                label: strings.chatDeleteAction,
                icon: AppIcons.delete,
                danger: true,
                onPressed: () {
                  popAppModal(context);
                  unawaited(_showDeleteDialog(context));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the full picker over the selector, and sets whatever comes back.
  ///
  /// Not a toggle: the panel is where a reaction is removed, and picking an
  /// emoji out of 1500 is an act of choosing rather than of undoing. Dismissing
  /// the picker leaves the message surface open, because the user has not
  /// finished with it.
  Future<void> _expandReactions(BuildContext context) async {
    final emoji = await showAppEmojiPicker(context);
    if (emoji == null || !context.mounted) {
      return;
    }
    popAppModal(context);
    onIntent(SetReactionIntent(messageId: message.id, emoji: emoji));
  }

  Future<void> _showDeleteDialog(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    await showAppDialog<void>(
      context: context,
      title: strings.chatDeleteTitle,
      body: strings.chatDeleteHonestMessage,
      actions: [
        AppButton(
          label: strings.chatCancelAction,
          kind: AppButtonKind.ghost,
          onPressed: () => popAppModal(context),
        ),
        AppButton(
          label: strings.chatDeleteForMeAction,
          kind: AppButtonKind.outline,
          onPressed: () {
            popAppModal(context);
            onIntent(DeleteForMeIntent(message.id));
          },
        ),
        if (message.canDeleteForEveryone)
          AppButton(
            label: strings.chatDeleteForEveryoneAction,
            kind: AppButtonKind.danger,
            onPressed: () {
              popAppModal(context);
              onIntent(DeleteForEveryoneIntent(message.id));
            },
          ),
      ],
    );
  }
}

final class _AttachmentMessageContent extends StatelessWidget {
  const _AttachmentMessageContent({
    required this.message,
    required this.onOpen,
  });

  final ChatMessageViewModel message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    final state = message.attachmentStates.isEmpty
        ? AttachmentTransferState.ready
        : message.attachmentStates.first;
    final ready = state == AttachmentTransferState.ready;
    final typeLabel = message.kind == ChatTimelineContentKind.image
        ? strings.attachmentImageLabel
        : strings.attachmentFileLabel;
    return Semantics(
      button: true,
      label: '$typeLabel: ${_attachmentStateLabel(strings, state)}',
      hint: ready ? strings.attachmentOpenHint : null,
      child: InkWell(
        onTap: message.attachments.isEmpty || !ready ? null : onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: AppRadii.control,
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  message.kind == ChatTimelineContentKind.image
                      ? AppIcons.attach
                      : AppIcons.attach,
                  color: colors.accent,
                ),
                const SizedBox(width: AppSpacing.x1),
                Flexible(
                  child: Text(
                    message.attachments.isEmpty || !ready
                        ? _attachmentStateLabel(strings, state)
                        : message.attachments.first.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatComposerBuilder extends StatefulWidget {
  const ChatComposerBuilder({
    required this.securityGate,
    required this.offline,
    required this.savedMessages,
    required this.onIntent,
    this.initialDraft,
    super.key,
  });

  final ChatSecurityGate securityGate;
  final bool offline;
  final bool savedMessages;
  final String? initialDraft;
  final ChatIntentCallback onIntent;

  @override
  State<ChatComposerBuilder> createState() => ChatComposerBuilderState();
}

class ChatComposerBuilderState extends State<ChatComposerBuilder> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  ChatComposerMode _mode = ChatComposerMode.compose;
  ChatMessageViewModel? _contextMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDraft)
      ..addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void handleIntent(ChatIntent intent) {
    switch (intent) {
      case ReplyToMessageIntent(:final message):
        setState(() {
          _mode = ChatComposerMode.reply;
          _contextMessage = message;
        });
        _focusNode.requestFocus();
      case BeginEditMessageIntent(:final message):
        setState(() {
          _mode = ChatComposerMode.edit;
          _contextMessage = message;
          _controller.text = message.text ?? '';
          _controller.selection = TextSelection.collapsed(
            offset: _controller.text.length,
          );
        });
        _focusNode.requestFocus();
      default:
        break;
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
    widget.onIntent(
      SaveDraftIntent(
        _controller.text.trim().isEmpty ? null : _controller.text,
      ),
    );
  }

  void _cancelContext() {
    setState(() {
      _mode = ChatComposerMode.compose;
      _contextMessage = null;
      _controller.clear();
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.securityGate != ChatSecurityGate.ready) return;
    final contextMessage = _contextMessage;
    if (_mode == ChatComposerMode.edit && contextMessage != null) {
      widget.onIntent(
        EditMessageIntent(messageId: contextMessage.id, text: text),
      );
    } else {
      widget.onIntent(
        SendTextIntent(
          text: text,
          replyToMessageId: _mode == ChatComposerMode.reply
              ? contextMessage?.id
              : null,
          quoteFallback: _mode == ChatComposerMode.reply
              ? contextMessage?.text
              : null,
        ),
      );
    }
    setState(() {
      _controller.clear();
      _mode = ChatComposerMode.compose;
      _contextMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final gate = widget.securityGate;
    if (gate != ChatSecurityGate.ready && gate != ChatSecurityGate.checking) {
      return _WithheldComposer(gate: gate);
    }
    // While trust is still being read the composer stays in place and inert
    // rather than being swapped for a banner. The answer usually lands within a
    // frame or two, and a control that disappears and comes back reads as a
    // fault; one that is briefly unavailable does not.
    final ready = gate == ChatSecurityGate.ready;
    return Material(
      color: context.tokens.colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: context.tokens.colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.offline)
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    color: context.tokens.colors.warning.withValues(
                      alpha: 0.14,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.x2),
                    child: Text(
                      strings.chatOfflineQueueNotice,
                      style: context.tokens.typography.compact,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (_contextMessage != null)
                _ComposerContextStrip(
                  mode: _mode,
                  message: _contextMessage!,
                  onCancel: _cancelContext,
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.x2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AppIconButton(
                      icon: AppIcons.attach,
                      semanticLabel: strings.chatAttachAction,
                      onPressed: ready
                          ? () => widget.onIntent(const OpenAttachmentIntent())
                          : null,
                      kind: AppButtonKind.ghost,
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 144),
                        child: TextField(
                          key: const ValueKey('chat-composer-field'),
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: ready,
                          minLines: 1,
                          maxLines: 6,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          maxLength: 16384,
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                maxLength,
                              }) => currentLength > 15000
                              ? Text(
                                  '$currentLength / $maxLength',
                                  style: context.tokens.typography.label,
                                )
                              : null,
                          decoration: InputDecoration(
                            hintText: widget.savedMessages
                                ? strings.savedMessagesComposerHint
                                : strings.chatComposerHint,
                            filled: true,
                            fillColor: context.tokens.colors.surfaceRaised,
                            border: const OutlineInputBorder(
                              borderRadius: AppRadii.control,
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) {
                            if (HardwareKeyboard.instance.isControlPressed) {
                              _submit();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.x1),
                    // The emoji button stays put. It used to be swapped out for
                    // Send as soon as the draft had a character in it, which
                    // meant an emoji could only ever be inserted into an empty
                    // field - and "insert at the caret" had nothing to insert
                    // into. Send appears beside it instead of in place of it.
                    AppIconButton(
                      icon: AppIcons.emoji,
                      semanticLabel: strings.chatEmojiAction,
                      onPressed: ready ? () => unawaited(_insertEmoji()) : null,
                      kind: AppButtonKind.ghost,
                    ),
                    if (_controller.text.trim().isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.x1),
                      AppIconButton(
                        icon: AppIcons.send,
                        semanticLabel: _mode == ChatComposerMode.edit
                            ? strings.chatSaveEditAction
                            : strings.chatSendAction,
                        onPressed: ready ? _submit : null,
                        kind: AppButtonKind.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the picker and inserts what comes back at the caret.
  ///
  /// Dismissing it returns null and changes nothing, so the draft the composer
  /// is holding survives a backdrop tap and a back gesture. An emoji is a
  /// grapheme cluster of more than one UTF-16 unit, so the caret moves by the
  /// string's length rather than by one.
  Future<void> _insertEmoji() async {
    final emoji = await showAppEmojiPicker(context);
    if (emoji == null || !mounted) {
      return;
    }
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }
}

class _OpenMessageMenuIntent extends Intent {
  const _OpenMessageMenuIntent();
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ListTile(
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
      onTap: onPressed,
    ),
  );
}

/// The floating panel of quick reactions that opens with the message actions.
///
/// One horizontally scrollable row on a raised rounded surface, ending in the
/// control that opens the full picker. It is a sibling of the action sheet
/// inside one route, which is what makes it keyboard reachable and traversable
/// by a screen reader; see [showAppAnchoredSheet].
class _ReactionSelector extends StatelessWidget {
  const _ReactionSelector({
    required this.selected,
    required this.onSelected,
    required this.onExpand,
  });

  /// The reaction this user has already set, marked as selected in the row.
  final String? selected;

  /// Called with the chosen emoji. Whether that sets or removes belongs to the
  /// caller, which is the only place that knows the current reaction.
  final ValueChanged<String> onSelected;

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: strings.chatReactionSelectorLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadii.pill,
            border: Border.all(color: colors.border),
            boxShadow: AppElevation.level2,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x1),
              child: Row(
                children: [
                  // Only the reactions scroll. The control that opens the full
                  // picker stays pinned to the trailing edge, because twenty-four
                  // targets are wider than any phone and an expand button a
                  // thousand pixels away is one nobody finds.
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final emoji in chatQuickReactions)
                            _ReactionOption(
                              emoji: emoji,
                              selected: emoji == selected,
                              onPressed: () => onSelected(emoji),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: AppSpacing.x6,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x1,
                    ),
                    color: colors.border,
                  ),
                  _ReactionExpandOption(onPressed: onExpand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReactionOption extends StatelessWidget {
  const _ReactionOption({
    required this.emoji,
    required this.selected,
    required this.onPressed,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: selected
          ? strings.chatReactionRemoveAction(emoji)
          : strings.chatReactionAddAction(emoji),
      child: InkResponse(
        onTap: onPressed,
        radius: AppFocus.minimumTarget / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppFocus.minimumTarget,
          height: AppFocus.minimumTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? colors.accentSoft : null,
            border: selected
                ? Border.all(color: colors.accent, width: 2)
                : null,
          ),
          // The glyph is a glyph in either direction; only the row around it
          // follows the locale.
          child: Text(
            emoji,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}

class _ReactionExpandOption extends StatelessWidget {
  const _ReactionExpandOption({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).chatMoreReactionsAction;
    final colors = context.tokens.colors;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onPressed,
          radius: AppFocus.minimumTarget / 2,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          child: Container(
            width: AppFocus.minimumTarget,
            height: AppFocus.minimumTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceRaised,
            ),
            child: AppIcon(AppIcons.add, color: colors.textPrimary, size: 20),
          ),
        ),
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onPressed});

  final ChatReactionViewModel reaction;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: reaction.selectedByCurrentUser,
    label: AppLocalizations.of(
      context,
    ).chatReactionSemantics(reaction.emoji, reaction.count),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadii.pill,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32, minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
          decoration: BoxDecoration(
            color: reaction.selectedByCurrentUser
                ? context.tokens.colors.accentSoft
                : context.tokens.colors.surfaceRaised,
            border: Border.all(
              color: reaction.selectedByCurrentUser
                  ? context.tokens.colors.accent
                  : context.tokens.colors.border,
            ),
            borderRadius: AppRadii.pill,
          ),
          alignment: Alignment.center,
          child: Text('${reaction.emoji} ${reaction.count}'),
        ),
      ),
    ),
  );
}

class _DeliveryIndicator extends StatelessWidget {
  const _DeliveryIndicator({required this.state});

  final ChatDeliveryViewState state;

  @override
  Widget build(BuildContext context) {
    if (state == ChatDeliveryViewState.received) {
      return const SizedBox.shrink();
    }
    final strings = AppLocalizations.of(context);
    final (icon, color) = switch (state) {
      ChatDeliveryViewState.localOnly => (
        AppIcons.saved,
        context.tokens.colors.textMuted,
      ),
      ChatDeliveryViewState.queued => (
        AppIcons.offlineQueue,
        context.tokens.colors.warning,
      ),
      ChatDeliveryViewState.encrypting => (
        AppIcons.security,
        context.tokens.colors.warning,
      ),
      ChatDeliveryViewState.sending => (
        AppIcons.clock,
        context.tokens.colors.textMuted,
      ),
      ChatDeliveryViewState.accepted => (
        AppIcons.accepted,
        context.tokens.colors.textMuted,
      ),
      ChatDeliveryViewState.delivered => (
        AppIcons.delivered,
        context.tokens.colors.success,
      ),
      ChatDeliveryViewState.read => (
        AppIcons.delivered,
        context.tokens.colors.accent,
      ),
      ChatDeliveryViewState.failed => (
        AppIcons.error,
        context.tokens.colors.danger,
      ),
      ChatDeliveryViewState.received => (
        AppIcons.info,
        context.tokens.colors.textMuted,
      ),
    };
    final label = _deliveryLabel(strings, state);
    return Tooltip(
      message: label,
      child: AppIcon(
        icon,
        color: color,
        size: 15,
        decorative: false,
        semanticLabel: label,
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = MaterialLocalizations.of(context).formatMediumDate(date);
    return Semantics(
      header: true,
      label: label,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x1,
          ),
          decoration: BoxDecoration(
            color: context.tokens.colors.surfaceRaised,
            borderRadius: AppRadii.pill,
          ),
          child: Text(label, style: context.tokens.typography.label),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).chatUnreadDivider;
    return Semantics(
      header: true,
      liveRegion: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.x3),
        child: Row(
          children: [
            Expanded(child: Divider(color: context.tokens.colors.accent)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
              child: Text(
                label,
                style: context.tokens.typography.label.copyWith(
                  color: context.tokens.colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(child: Divider(color: context.tokens.colors.accent)),
          ],
        ),
      ),
    );
  }
}

class _PaginationMarker extends StatelessWidget {
  const _PaginationMarker({
    required this.hasMore,
    required this.loading,
    required this.failed,
    required this.onLoad,
  });

  final bool hasMore;
  final bool loading;
  final bool failed;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Center(
          child: Semantics(
            label: strings.chatLoadingOlder,
            child: const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (failed) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: AppButton(
          label: strings.chatOlderErrorAction,
          onPressed: onLoad,
          leading: AppIcons.retry,
          kind: AppButtonKind.outline,
        ),
      );
    }
    if (!hasMore) {
      return Semantics(
        label: strings.chatBeginningOfHistory,
        child: const SizedBox(height: AppSpacing.x4),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x2),
      child: TextButton(
        onPressed: onLoad,
        child: Text(strings.chatLoadOlderAction),
      ),
    );
  }
}

class _ComposerContextStrip extends StatelessWidget {
  const _ComposerContextStrip({
    required this.mode,
    required this.message,
    required this.onCancel,
  });

  final ChatComposerMode mode;
  final ChatMessageViewModel message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final label = mode == ChatComposerMode.edit
        ? strings.chatEditingMessage
        : strings.chatReplyingTo(message.authorName);
    return Semantics(
      container: true,
      label: label,
      child: Container(
        width: double.infinity,
        color: context.tokens.colors.surfaceRaised,
        padding: const EdgeInsetsDirectional.only(
          start: AppSpacing.x4,
          top: AppSpacing.x2,
          bottom: AppSpacing.x2,
        ),
        child: Row(
          children: [
            AppIcon(
              mode == ChatComposerMode.edit ? AppIcons.edit : AppIcons.reply,
              color: context.tokens.colors.accent,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: context.tokens.typography.label.copyWith(
                      color: context.tokens.colors.accent,
                    ),
                  ),
                  Text(
                    message.text ?? strings.chatDeletedMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.tokens.typography.compact,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: AppIcons.close,
              semanticLabel: strings.chatCancelContextAction,
              onPressed: onCancel,
              kind: AppButtonKind.ghost,
            ),
          ],
        ),
      ),
    );
  }
}

class _WithheldComposer extends StatelessWidget {
  const _WithheldComposer({required this.gate});

  final ChatSecurityGate gate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (gate) {
      // Neither gate withholds a message, so neither reaches this widget.
      ChatSecurityGate.checking || ChatSecurityGate.ready => '',
      ChatSecurityGate.unverifiedIdentity =>
        strings.chatWithheldUnverifiedIdentity,
      ChatSecurityGate.unverifiedDevice => strings.chatWithheldUnverifiedDevice,
      ChatSecurityGate.masterKeyChanged => strings.chatWithheldMasterChanged,
      ChatSecurityGate.deviceLogFork => strings.chatWithheldLogFork,
      ChatSecurityGate.postQuantumUnavailable => strings.chatWithheldPq,
      ChatSecurityGate.groupUpdating => strings.groupWithheldUpdating,
      ChatSecurityGate.groupRemoved => strings.groupWithheldRemoved,
      ChatSecurityGate.groupQueueGap => strings.groupWithheldQueueGap,
      ChatSecurityGate.groupConflict => strings.groupWithheldConflict,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Material(
        color: context.tokens.colors.surface,
        child: SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.tokens.colors.danger),
              ),
            ),
            child: Row(
              children: [
                AppIcon(AppIcons.security, color: context.tokens.colors.danger),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Text(
                    message,
                    style: context.tokens.typography.compact.copyWith(
                      color: context.tokens.colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemMessageContent extends StatelessWidget {
  const _SystemMessageContent({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      AppIcon(AppIcons.info, color: context.tokens.colors.textMuted, size: 16),
      const SizedBox(width: AppSpacing.x2),
      Flexible(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: context.tokens.typography.compact.copyWith(
            color: context.tokens.colors.textMuted,
          ),
        ),
      ),
    ],
  );
}

class _UnsupportedMessageContent extends StatelessWidget {
  const _UnsupportedMessageContent();

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).chatUnsupportedMessage;
    return Row(
      children: [
        AppIcon(AppIcons.unsupported, color: context.tokens.colors.warning),
        const SizedBox(width: AppSpacing.x2),
        Expanded(child: Text(label, style: context.tokens.typography.compact)),
      ],
    );
  }
}

BorderRadius _bubbleRadius(ChatMessageViewModel message) {
  const regular = Radius.circular(20);
  const grouped = Radius.circular(8);
  if (!message.lastInAuthorGroup) return AppRadii.message;
  return message.outgoing
      ? const BorderRadius.only(
          topLeft: regular,
          topRight: regular,
          bottomLeft: regular,
          bottomRight: grouped,
        )
      : const BorderRadius.only(
          topLeft: regular,
          topRight: regular,
          bottomLeft: grouped,
          bottomRight: regular,
        );
}

TextDirection? _contentDirection(String? text) {
  if (text == null || text.isEmpty) return null;
  final firstStrong = RegExp(
    r'[\u0590-\u08ff]|[A-Za-z]',
  ).firstMatch(text)?.group(0);
  if (firstStrong == null) return null;
  return RegExp(r'[\u0590-\u08ff]').hasMatch(firstStrong)
      ? TextDirection.rtl
      : TextDirection.ltr;
}

String _attachmentStateLabel(
  AppLocalizations strings,
  AttachmentTransferState state,
) => switch (state) {
  AttachmentTransferState.queued => strings.attachmentQueuedState,
  AttachmentTransferState.encrypting => strings.chatStateEncrypting,
  AttachmentTransferState.uploading => strings.chatStateSending,
  AttachmentTransferState.sending => strings.chatStateSending,
  AttachmentTransferState.downloading => strings.attachmentDownloadingState,
  AttachmentTransferState.verifying => strings.attachmentVerifyingState,
  AttachmentTransferState.ready => strings.attachmentReadyState,
  AttachmentTransferState.expired => strings.attachmentExpiredState,
  AttachmentTransferState.cancelled => strings.attachmentCancelledState,
  AttachmentTransferState.quotaExceeded => strings.attachmentQuotaState,
  AttachmentTransferState.unsupported => strings.attachmentUnsupportedState,
  AttachmentTransferState.corrupt => strings.attachmentCorruptState,
  AttachmentTransferState.failed => strings.attachmentFailedState,
};

String _deliveryLabel(AppLocalizations strings, ChatDeliveryViewState state) =>
    switch (state) {
      ChatDeliveryViewState.localOnly => strings.chatStateLocalOnly,
      ChatDeliveryViewState.queued => strings.chatStateQueued,
      ChatDeliveryViewState.encrypting => strings.chatStateEncrypting,
      ChatDeliveryViewState.sending => strings.chatStateSending,
      ChatDeliveryViewState.accepted => strings.chatStateAccepted,
      ChatDeliveryViewState.delivered => strings.chatStateDelivered,
      ChatDeliveryViewState.read => strings.chatStateRead,
      ChatDeliveryViewState.failed => strings.chatStateFailed,
      ChatDeliveryViewState.received => strings.chatStateReceived,
    };
