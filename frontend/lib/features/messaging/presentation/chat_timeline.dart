import 'dart:async';
import 'dart:math' as math;

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_emoji_picker.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_text_direction.dart';
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
  State<ChatTimelineAdapter> createState() => ChatTimelineAdapterState();
}

class ChatTimelineAdapterState extends State<ChatTimelineAdapter> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _distanceFromBottom = ValueNotifier(0);

  /// The rows that are mounted right now, and nothing else.
  ///
  /// This replaces a `Map<String, GlobalKey>` that was written to for every
  /// message ever drawn and read from for every one of them on every anchor
  /// capture, and was never pruned — so both its size and the cost of using it
  /// were set by how long the reader had been scrolling. A row registers
  /// itself while it is mounted and takes itself out when it is not, which
  /// bounds this by what the viewport and its cache extent hold. It is also
  /// the only set an anchor could ever have come from: an unmounted row has no
  /// render object to measure.
  final Map<String, _AnchoredRowState> _anchoredRows = {};

  /// The rows most recently built, so that a rebuild which changes one message
  /// hands every other row back the identical widget instance.
  ///
  /// `Element.updateChild` skips a child whose new widget is the one it
  /// already holds, so an unchanged row is not merely cheap to rebuild — it is
  /// not rebuilt at all. Two generations rather than one so that a generation
  /// filling up does not throw away the rows on screen; the older one is
  /// dropped whole, which is what keeps this from becoming a second unbounded
  /// map of everything ever drawn.
  var _renderedRows = <Key, _RenderedRow>{};
  var _previousRenderedRows = <Key, _RenderedRow>{};

  _TimelineRows? _rows;
  List<ChatMessageViewModel>? _rowsSource;
  var _rowsStart = -1;

  var _visibleMessageCount = 0;
  var _loadRequestSent = false;
  _ReadingAnchor? _pendingAnchor;
  _ReadingAnchor? _lastReadingAnchor;

  /// A jump whose target was not loaded when it was asked for.
  ///
  /// The application answers a jump by widening the window, which arrives as a
  /// later build with the same highlighted id. Without this the second build
  /// takes the "nothing changed" branch and the jump is silently dropped, which
  /// is exactly how a windowed timeline turns search and the pinned banner into
  /// taps that do nothing.
  String? _unresolvedJump;
  var _anchorSnapshotScheduled = false;
  var _dependenciesInitialized = false;

  /// How many rows are registered for anchoring, for the bounding test.
  @visibleForTesting
  int get anchoredRowCount => _anchoredRows.length;

  /// How many row widgets are being held for reuse, for the bounding test.
  @visibleForTesting
  int get retainedRowCount =>
      {..._renderedRows.keys, ..._previousRenderedRows.keys}.length;

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
    // Every retained row holds the callback it was built with. A new one is a
    // different destination for the same tap, so nothing built against the old
    // one may be handed back.
    if (oldWidget.onIntent != widget.onIntent) {
      _renderedRows = {};
      _previousRenderedRows = {};
    }
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
    final pendingJump = _unresolvedJump;
    if (widget.model.highlightedMessageId !=
        oldWidget.model.highlightedMessageId) {
      _dropReadingAnchor();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfRequested(widget.model.highlightedMessageId);
      });
    } else if (pendingJump != null &&
        widget.model.messages.any((message) => message.id == pendingJump)) {
      _dropReadingAnchor();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpIfRequested(pendingJump);
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
    }
  }

  /// Forgets where the reader was, because they asked to be somewhere else.
  ///
  /// A jump decides the position outright. An anchor captured a moment before
  /// it — in `didUpdateWidget`, or standing from the last scroll — describes a
  /// line the reader has just left, and restoring it mid-jump takes the
  /// position back: a row materialising during the scroll reports its size,
  /// and the correction that answers that report cancels the animation.
  void _dropReadingAnchor() {
    _pendingAnchor = null;
    _lastReadingAnchor = null;
  }

  /// Keeps a standing anchor only for as long as it is worth anything.
  ///
  /// The standing anchor exists for one consumer: a row that changes size
  /// after the fact, which arrives as a notification once the new layout has
  /// already happened and so cannot capture its own "before". Everything else
  /// captures at the moment it needs one.
  ///
  /// While the reader is scrolling, the position is theirs and a correction
  /// computed against a reading captured before the gesture would fight them —
  /// so the standing anchor is dropped when a scroll starts and taken again
  /// when it ends. That is the whole of the per-tick capture this replaces.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _lastReadingAnchor = null;
    } else if (notification is ScrollEndNotification) {
      _scheduleAnchorSnapshot();
    }
    return false;
  }

  void _scheduleAnchorSnapshot() {
    if (_anchorSnapshotScheduled) return;
    _anchorSnapshotScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorSnapshotScheduled = false;
      if (!mounted) return;
      // Never while the viewport is moving. A reading captured mid-scroll
      // describes a line that is already somewhere else, and correcting
      // towards it stops the scroll dead.
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      _lastReadingAnchor = _captureReadingAnchor();
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
    for (final entry in _anchoredRows.entries) {
      final render = entry.value.anchorBox;
      if (render == null) continue;
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
    final render = _anchoredRows[anchor.messageId]?.anchorBox;
    if (render == null) return;
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
    if (sourceIndex < 0) {
      // Outside the loaded window. The request is remembered rather than
      // dropped, and runs again when the page carrying the target arrives.
      _unresolvedJump = messageId;
      return;
    }
    _unresolvedJump = null;
    final needed = widget.model.messages.length - sourceIndex;
    if (needed > _visibleMessageCount) {
      setState(() => _visibleMessageCount = needed);
    }
    // The scroll runs a frame later, after any widening above has been laid
    // out and the extent it can be clamped to is real. Nothing else asks for
    // that frame: a jump to a target that is already drawn and already inside
    // the drawn range changes no state at all, and the tap did nothing.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final reverseIndex = widget.model.messages.length - 1 - sourceIndex;
      // The drawn range's own average row height, rather than a constant that
      // is only right for one text size and one bubble. A constant wrong by a
      // fifth lands a jump a screen away from its target — and the correction
      // below can only run on a target the estimate got close enough to build.
      final perRow =
          (position.maxScrollExtent + position.viewportDimension) /
          math.max(1, _visibleMessageCount);
      final target = (reverseIndex * perRow).clamp(
        0.0,
        position.maxScrollExtent,
      );
      final reducedMotion = MediaQuery.disableAnimationsOf(context);
      final settled = animate && !reducedMotion
          ? _scrollController.animateTo(
              target,
              duration: AppMotion.route,
              curve: AppMotion.enter,
            )
          : Future<void>.sync(() => _scrollController.jumpTo(target));
      unawaited(
        settled.then((_) {
          if (!mounted) return;
          // The registry answers this exactly as the key map did: a row that
          // is not mounted has no context either way. Asked once the scroll
          // has settled rather than while it is still running, so the target
          // has been built by the time it is looked for.
          final targetContext = _anchoredRows[messageId]?.context;
          if (targetContext == null || !targetContext.mounted) return;
          unawaited(
            Scrollable.ensureVisible(
              targetContext,
              alignment: 0.5,
              duration: reducedMotion ? Duration.zero : AppMotion.state,
            ),
          );
        }),
      );
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
    final start = math.max(
      0,
      widget.model.messages.length - _visibleMessageCount,
    );
    final rows = _rowsFor(widget.model.messages, start);
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
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: ListView.builder(
                key: const PageStorageKey('chat-timeline'),
                controller: _scrollController,
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x3,
                  AppSpacing.x8,
                  AppSpacing.x3,
                  AppSpacing.x4,
                ),
                itemCount: rows.rows.length + 1,
                // Every row carries a key of its own, so a message arriving at
                // the newest end shifts every index without invalidating a
                // single element: the sliver looks each key up here and moves
                // its element to the new slot. Without it, keyed children whose
                // index changed would all be discarded and rebuilt — which is
                // what the `GlobalKey` per message used to prevent, at the
                // price of a re-parent per row per arrival.
                findChildIndexCallback: (key) => rows.indexOf(key),
                itemBuilder: (context, reverseIndex) {
                  if (reverseIndex == rows.rows.length) {
                    return _PaginationMarker(
                      key: _paginationRowKey,
                      hasMore: start > 0 || widget.model.hasMoreBefore,
                      loading: widget.model.loadingBefore,
                      failed: widget.model.olderLoadFailed,
                      onLoad: _loadOlder,
                    );
                  }
                  return _rowWidget(
                    rows.rows[rows.rows.length - 1 - reverseIndex],
                  );
                },
              ),
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

  /// The drawn range's rows, rebuilt only when that range changed.
  ///
  /// The projection behind the model hands back the identical view model for
  /// every message it did not re-derive, so "did this range change" is a walk
  /// of object identities rather than a re-derivation of separators, days and
  /// the unread line for a window that may hold the whole conversation.
  _TimelineRows _rowsFor(List<ChatMessageViewModel> messages, int start) {
    final cached = _rows;
    if (cached != null &&
        _rowsStart == start &&
        _sameDrawnRange(messages, start)) {
      return cached;
    }
    final rows = <_TimelineRow>[];
    int? previousDay;
    var unreadInserted = false;
    for (var index = start; index < messages.length; index++) {
      final message = messages[index];
      final at = message.timestamp;
      // Compared as an integer and only built into a `DateTime` on the days
      // that get a heading. Constructing one per message means a timezone
      // conversion per message, for an answer that changes about once a
      // hundred rows.
      final day = at.year * 10000 + at.month * 100 + at.day;
      if (day != previousDay) {
        rows.add(_DateRow(DateTime(at.year, at.month, at.day), message.id));
        previousDay = day;
      }
      if (!unreadInserted && message.unread) {
        rows.add(_UnreadRow(message.id));
        unreadInserted = true;
      }
      rows.add(_MessageRow(message));
    }
    final built = _TimelineRows(rows);
    _rows = built;
    _rowsSource = messages;
    _rowsStart = start;
    return built;
  }

  bool _sameDrawnRange(List<ChatMessageViewModel> messages, int start) {
    final previous = _rowsSource;
    if (previous == null) return false;
    if (identical(previous, messages)) return true;
    if (previous.length != messages.length) return false;
    for (var index = start; index < messages.length; index++) {
      if (!identical(previous[index], messages[index])) return false;
    }
    return true;
  }

  /// One row's widget, reused verbatim when nothing about that row moved.
  ///
  /// Rows are built during layout as well as during build — a scroll
  /// materialises children without the adapter rebuilding at all — so the
  /// generation rolls on size rather than on frames. A viewport and its cache
  /// extent are a few dozen rows; a generation that has taken more than
  /// [_rowGenerationLimit] has certainly moved on from the ones it started
  /// with.
  Widget _rowWidget(_TimelineRow row) {
    if (_renderedRows.length >= _rowGenerationLimit) {
      _previousRenderedRows = _renderedRows;
      _renderedRows = {};
    }
    final highlighted =
        row is _MessageRow &&
        widget.model.highlightedMessageId == row.message.id;
    final key = row.key;
    final retained = _renderedRows[key] ?? _previousRenderedRows[key];
    if (retained != null && retained.draws(row, highlighted: highlighted)) {
      _renderedRows[key] = retained;
      return retained.widget;
    }
    final built = switch (row) {
      _MessageRow(:final message) => _AnchoredRow(
        key: key,
        messageId: message.id,
        rows: _anchoredRows,
        child: SizeChangedLayoutNotifier(
          child: ChatMessageBuilder(
            message: message,
            highlighted: highlighted,
            onIntent: widget.onIntent,
            onJumpToReply: (id) {
              widget.onIntent(JumpToMessageIntent(id));
              _jumpIfRequested(id);
            },
          ),
        ),
      ),
      _DateRow(:final date) => _DateSeparator(key: key, date: date),
      _UnreadRow() => _UnreadDivider(key: key),
    };
    _renderedRows[key] = _RenderedRow(
      row: row,
      highlighted: highlighted,
      widget: built,
    );
    return built;
  }
}

const _paginationRowKey = ValueKey('timeline-pagination');

/// How many rows one generation of the reuse cache takes before it rolls.
const _rowGenerationLimit = 64;

/// The drawn rows, and the index each of their keys sits at.
final class _TimelineRows {
  _TimelineRows(this.rows);

  final List<_TimelineRow> rows;

  /// Built on the first relocation and not before. A rebuild that leaves every
  /// index where it was never asks, and paying for the index then would be a
  /// walk of the whole drawn range for nothing.
  late final Map<Key, int> _indexByKey = {
    for (var index = 0; index < rows.length; index++) rows[index].key: index,
  };

  /// Where the sliver should now look for the child that carries [key].
  ///
  /// The list is drawn reversed, so the row at the end of [rows] is the child
  /// at index zero.
  int? indexOf(Key key) {
    if (key == _paginationRowKey) return rows.length;
    final index = _indexByKey[key];
    return index == null ? null : rows.length - 1 - index;
  }
}

/// A row widget that is still good, and what it was drawn from.
final class _RenderedRow {
  const _RenderedRow({
    required this.row,
    required this.highlighted,
    required this.widget,
  });

  final _TimelineRow row;
  final bool highlighted;
  final Widget widget;

  bool draws(_TimelineRow other, {required bool highlighted}) {
    if (this.highlighted != highlighted) return false;
    return switch ((row, other)) {
      (_MessageRow(message: final mine), _MessageRow(message: final theirs)) =>
        identical(mine, theirs),
      (_DateRow(date: final mine), _DateRow(date: final theirs)) =>
        mine == theirs,
      (_UnreadRow(), _UnreadRow()) => true,
      _ => false,
    };
  }
}

sealed class _TimelineRow {
  const _TimelineRow();

  /// This row's identity in the list, so the sliver can follow it when an
  /// arrival at the newest end shifts every index by one.
  Key get key;
}

final class _MessageRow extends _TimelineRow {
  _MessageRow(this.message) : key = ValueKey('timeline-message-${message.id}');

  final ChatMessageViewModel message;

  @override
  final Key key;
}

/// A day heading, identified by the message it sits above.
///
/// Not by the day it names: a skewed timestamp can put the same day on both
/// sides of another one, and two rows sharing a key is a crash rather than a
/// wrong heading. The message below it is unique and does not move when an
/// older page is prepended.
final class _DateRow extends _TimelineRow {
  _DateRow(this.date, String anchorMessageId)
    : key = ValueKey('timeline-date-$anchorMessageId');

  final DateTime date;

  @override
  final Key key;
}

final class _UnreadRow extends _TimelineRow {
  _UnreadRow(String anchorMessageId)
    : key = ValueKey('timeline-unread-$anchorMessageId');

  @override
  final Key key;
}

/// One drawn message, registered for as long as it is on screen.
///
/// The registration is the anchor mechanism: the reading line is the topmost
/// row the viewport is showing, and only a mounted row has a box to measure.
/// Because the entry lives exactly as long as the element does, the set cannot
/// outgrow what the list has materialised.
class _AnchoredRow extends StatefulWidget {
  const _AnchoredRow({
    required this.messageId,
    required this.rows,
    required this.child,
    super.key,
  });

  final String messageId;
  final Map<String, _AnchoredRowState> rows;
  final Widget child;

  @override
  State<_AnchoredRow> createState() => _AnchoredRowState();
}

class _AnchoredRowState extends State<_AnchoredRow> {
  RenderBox? get anchorBox {
    final render = context.findRenderObject();
    return render is RenderBox && render.attached ? render : null;
  }

  @override
  void initState() {
    super.initState();
    widget.rows[widget.messageId] = this;
  }

  @override
  void dispose() {
    if (identical(widget.rows[widget.messageId], this)) {
      widget.rows.remove(widget.messageId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
    // A fraction of the row is the bubble's *limit*, not its size.
    // `FractionallySizedBox` passes a tight width down, so every bubble was
    // exactly 82% of the row whatever it held, and a two-word message drew a
    // reaction row and a timestamp across empty space. A maximum leaves the
    // width to the content and keeps the long-message behaviour identical.
    return LayoutBuilder(
      builder: (context, constraints) {
        final widthClass = AppBreakpoints.of(MediaQuery.sizeOf(context).width);
        final limit = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Align(
          alignment: message.outgoing
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  limit * (widthClass == AppWidthClass.narrow ? 0.82 : 0.70),
            ),
            child: bubble,
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    // `stretch` is what forced a bubble to fill whatever width it was given:
    // a stretched column takes `constraints.maxWidth`, so the maximum set
    // above would have been the size again. Aligning to the message's own side
    // lets every row size to itself, which is the whole point of the change.
    final align = message.outgoing
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
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
            textDirection: resolveFirstStrongDirection(message.text),
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
        // This row is the one the reader called out: under `stretch` it was
        // handed the bubble's full width whatever it held, so a single chip sat
        // in a box the size of the message. Under a column that no longer
        // stretches the `Wrap` takes the width of its chips and opens a new run
        // once the bubble's width is used up.
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
        // The metadata keeps a row of its own rather than joining the last line
        // of text. Beside the text it fits at one width and not at the next, so
        // a bubble's height would start depending on the viewport, and a resize
        // would hand the reading anchor a height change it cannot correct in
        // one pass. On its own row the height is the same at every width, and
        // the row follows the column: trailing on this user's own messages,
        // leading on the other side's.
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
        // No `Align` around the retry: an `Align` takes the width it is offered
        // and would put the bubble back at its maximum. A failed send is always
        // this user's own, so the column's trailing alignment is already the
        // alignment this button wants.
        if (message.delivery == ChatDeliveryViewState.failed)
          TextButton.icon(
            onPressed: () => onIntent(RetryMessageIntent(message)),
            icon: AppIcon(AppIcons.retry, color: colors.danger, size: 16),
            label: Text(strings.chatRetrySendAction),
            style: TextButton.styleFrom(foregroundColor: colors.danger),
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

class ChatComposerBuilderState extends State<ChatComposerBuilder>
    with WidgetsBindingObserver {
  /// How long the composer waits before writing a draft down.
  ///
  /// Long enough that an ordinary run of typing is one write rather than one
  /// per character, short enough that a pause is already saved before the user
  /// has decided to leave. It bounds how stale the stored draft can be only
  /// while the field is being typed into: every way out of the composer
  /// flushes first, so the debounce never decides what survives.
  static const draftDebounce = Duration(milliseconds: 500);

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  ChatComposerMode _mode = ChatComposerMode.compose;
  ChatMessageViewModel? _contextMessage;
  bool _emojiPanelOpen = false;
  Timer? _draftTimer;

  /// The draft local storage is known to be holding.
  ///
  /// Kept so that a flush with nothing new to say writes nothing, which is
  /// what makes the flush safe to call from five places that can all happen at
  /// once — a blur, a pop and a lifecycle change arrive together when somebody
  /// swipes back out of a conversation.
  String? _persistedDraft;

  @override
  void initState() {
    super.initState();
    _persistedDraft = _draftOf(widget.initialDraft);
    _controller = TextEditingController(text: widget.initialDraft)
      ..addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ChatComposerBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The stored draft is read once and can land a frame after the composer
    // has been built. Adopting it then is what lets that read be a one-shot
    // rather than a subscription the composer would be feeding its own
    // keystrokes back into; adopting it only into an untouched empty field is
    // what stops it overwriting anything typed since.
    if (widget.initialDraft != oldWidget.initialDraft &&
        oldWidget.initialDraft == null &&
        _controller.text.isEmpty) {
      _persistedDraft = _draftOf(widget.initialDraft);
      _controller.value = TextEditingValue(
        text: widget.initialDraft ?? '',
        selection: TextSelection.collapsed(
          offset: widget.initialDraft?.length ?? 0,
        ),
      );
    }
  }

  @override
  void dispose() {
    // Before the controller goes, because its text is what is being saved.
    _flushDraft();
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  /// The draft a field holds, or null when it holds nothing worth keeping.
  static String? _draftOf(String? text) =>
      text == null || text.trim().isEmpty ? null : text;

  /// Writes the draft down now, if it differs from what is already stored.
  ///
  /// Every exit from the composer runs through here: losing focus, the route
  /// popping, the application leaving the foreground, the widget being
  /// disposed, and sending. A debounce that dropped the last few characters
  /// when somebody backgrounded the application would be a worse bug than the
  /// writes it was introduced to remove.
  void _flushDraft() {
    _draftTimer?.cancel();
    _draftTimer = null;
    final draft = _draftOf(_controller.text);
    if (draft == _persistedDraft) return;
    _persistedDraft = draft;
    widget.onIntent(SaveDraftIntent(draft));
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _flushDraft();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushDraft();
  }

  void handleIntent(ChatIntent intent) {
    switch (intent) {
      case ReplyToMessageIntent(:final message):
        setState(() {
          _mode = ChatComposerMode.reply;
          _contextMessage = message;
          _emojiPanelOpen = false;
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
          _emojiPanelOpen = false;
        });
        _focusNode.requestFocus();
      default:
        break;
    }
  }

  /// A keystroke costs a timer, and nothing else.
  ///
  /// It used to cost a `setState` and a write to the `conversations` row —
  /// which invalidated the conversation list, which rebuilt the page around
  /// this composer, which re-derived the whole loaded window. Typing twenty
  /// characters did that twenty times. The Send button's appearance is the
  /// only thing on this screen that follows the text, and it listens to the
  /// controller itself.
  void _onTextChanged() {
    _draftTimer?.cancel();
    _draftTimer = Timer(draftDebounce, _flushDraft);
  }

  void _cancelContext() {
    setState(() {
      _mode = ChatComposerMode.compose;
      _contextMessage = null;
      _controller.clear();
      _emojiPanelOpen = false;
    });
  }

  /// Swaps the emoji panel for the soft keyboard, or back.
  ///
  /// The two never stack: opening drops focus so the keyboard retracts and the
  /// panel takes the space it leaves, and closing asks for focus back. The
  /// draft and the caret belong to the controller, which neither transition
  /// touches.
  void _toggleEmojiPanel() {
    final opening = !_emojiPanelOpen;
    if (opening) {
      _focusNode.unfocus();
    }
    setState(() => _emojiPanelOpen = opening);
    if (!opening) {
      _focusNode.requestFocus();
    }
  }

  void _closeEmojiPanel() {
    if (!_emojiPanelOpen) return;
    setState(() => _emojiPanelOpen = false);
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
      _emojiPanelOpen = false;
    });
    // The message has left; the draft it used to be must not outlive it by
    // half a second, or a conversation reopened inside that window shows the
    // text back as though it had never been sent.
    _flushDraft();
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
    return PopScope(
      // Back closes the panel before it leaves the conversation, the way it
      // dismisses a keyboard rather than the screen behind one.
      canPop: !_emojiPanelOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _closeEmojiPanel();
          return;
        }
        _flushDraft();
      },
      child: Material(
        color: context.tokens.colors.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: context.tokens.colors.border),
            ),
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
                            ? () =>
                                  widget.onIntent(const OpenAttachmentIntent())
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
                                    // A spliced numeric expression, and the
                                    // only place in this file where two
                                    // independent runs share one paragraph.
                                    // Under an RTL ambient direction the two
                                    // numbers are EN, the separator is
                                    // neutral, and UAX #9 N1 resolves it to
                                    // the base direction, which reverses the
                                    // pair: `20 / 500` renders as
                                    // `500 / 20`. The expression reads left to
                                    // right in either locale, so it says so.
                                    textDirection: TextDirection.ltr,
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
                        icon: _emojiPanelOpen
                            ? AppIcons.keyboard
                            : AppIcons.emoji,
                        semanticLabel: _emojiPanelOpen
                            ? strings.chatEmojiPanelCloseAction
                            : strings.chatEmojiAction,
                        onPressed: ready ? _toggleEmojiPanel : null,
                        kind: AppButtonKind.ghost,
                      ),
                      // Send follows the text without the composer following
                      // it. The controller is a listenable, so the button is
                      // the only thing that rebuilds when a character lands.
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) =>
                            value.text.trim().isEmpty
                            ? const SizedBox.shrink()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: AppSpacing.x1),
                                  AppIconButton(
                                    icon: AppIcons.send,
                                    semanticLabel:
                                        _mode == ChatComposerMode.edit
                                        ? strings.chatSaveEditAction
                                        : strings.chatSendAction,
                                    onPressed: ready ? _submit : null,
                                    kind: AppButtonKind.primary,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                // The panel is part of the composer, not a sheet over it: it
                // stays open across as many selections as the user wants, and
                // the field it is typing into stays visible directly above it.
                // Insertion at the caret and grapheme-wise backspace are the
                // package's own, driven by the controller handed to it.
                if (_emojiPanelOpen)
                  AppEmojiPicker(controller: _controller, showBackspace: true),
              ],
            ),
          ),
        ),
      ),
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
          // No `alignment`: a `Container` given one wraps its child in an
          // `Align`, which takes every pixel it is offered, and that is what
          // drew one chip as a pill the width of the whole message. The minimum
          // width reaches the text through the container's constraints instead,
          // so `textAlign` centres a short label inside a chip that is still
          // only as wide as it needs to be.
          child: Text(
            '${reaction.emoji} ${reaction.count}',
            textAlign: TextAlign.center,
          ),
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
  const _DateSeparator({required this.date, super.key});

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
  const _UnreadDivider({super.key});

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
    super.key,
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
