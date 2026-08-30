import 'dart:async';
import 'dart:math' as math;

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/messaging/presentation/chat_message_builder.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

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
