import 'dart:async';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';

/// How many messages one read of the timeline asks the database for.
///
/// Larger than the widget's first render (80) so that the first screen is full
/// without a second read, and larger than the widget's own page step (60) so
/// that scrolling back usually costs nothing but a wider slice of what is
/// already in memory. The two windows compose: the widget widens what it draws
/// until it has drawn everything loaded, and only then does it ask for this.
const conversationTimelinePageSize = 120;

/// What the timeline is showing and what it is doing about showing more.
final class ConversationTimelineState {
  const ConversationTimelineState({
    required this.page,
    required this.loadingBefore,
    required this.olderLoadFailed,
  });

  final ConversationMessagePage page;

  /// A page of older messages has been asked for and has not landed.
  final bool loadingBefore;

  /// The last request for older messages failed, and the marker offers a retry.
  final bool olderLoadFailed;
}

/// The moving window one conversation is read through.
///
/// It owns two things the repository deliberately does not: which range is
/// currently loaded, and what to do when the user asks for more. Both live here
/// rather than in the provider's identity, because a window that is part of the
/// provider's key would tear the stream down and rebuild it on every page —
/// which drops the reader's scroll position, the thing paging backwards exists
/// to preserve.
final class ConversationTimelineWindow {
  ConversationTimelineWindow({
    required this.repository,
    required this.currentUserId,
    required this.conversationId,
    this.pageSize = conversationTimelinePageSize,
  }) : _window = NewestConversationMessages(pageSize);

  final ConversationRepositoryPort repository;
  final String currentUserId;
  final String conversationId;
  final int pageSize;

  final StreamController<ConversationTimelineState> _states =
      StreamController<ConversationTimelineState>.broadcast();
  StreamSubscription<ConversationMessagePage>? _subscription;
  ConversationMessageWindow _window;
  ConversationTimelineState? _latest;
  var _loadingBefore = false;
  var _olderLoadFailed = false;
  var _closed = false;

  /// The window's emissions, starting from whatever it is already showing.
  ///
  /// Replaying the last state matters because the database subscription
  /// outlives any one listener: a screen that comes back to a window already
  /// holding four pages must not be shown an empty timeline while the first
  /// page is re-read.
  Stream<ConversationTimelineState> get states async* {
    _subscription ??= _subscribe(_window);
    if (_latest case final latest?) {
      yield latest;
    }
    yield* _states.stream;
  }

  /// Widens the window by one page, downwards.
  ///
  /// The next lower bound is asked for by key rather than by offset, so this
  /// reads one page and stops instead of re-reading everything newer than it.
  Future<void> loadOlder() async {
    if (_closed || _loadingBefore) return;
    final page = _latest?.page;
    final oldest = page?.oldest;
    if (page == null || oldest == null || !page.hasMoreBefore) return;
    _loadingBefore = true;
    _olderLoadFailed = false;
    _republish();
    final next = await repository.olderMessageCursor(
      conversationId: conversationId,
      before: oldest,
      count: pageSize,
    );
    if (_closed) return;
    switch (next) {
      case Success(value: final cursor?):
        _retarget(ConversationMessagesFrom(cursor));
      case Success():
        // Nothing older after all. The next emission settles `hasMoreBefore`.
        _loadingBefore = false;
        _republish();
      case FailureResult():
        _loadingBefore = false;
        _olderLoadFailed = true;
        _republish();
    }
  }

  /// Opens the window far enough back to contain [messageId].
  ///
  /// Search, a reply quote and the pinned banner can all name a message older
  /// than anything loaded, and a window that made that the common case would
  /// turn each of them into a tap that does nothing. A page's worth of context
  /// is loaded below the target so it does not land against the top edge.
  Future<void> reveal(String messageId) async {
    if (_closed) return;
    final page = _latest?.page;
    if (page == null) return;
    if (page.messages.any((message) => message.messageId == messageId)) {
      return;
    }
    final target = await repository.messageCursor(
      conversationId: conversationId,
      messageId: messageId,
    );
    if (_closed || target is! Success<ConversationMessageCursor?>) return;
    final cursor = target.value;
    if (cursor == null) return;
    final oldest = _latest?.page.oldest;
    if (oldest != null && cursor.compareTo(oldest) >= 0) return;
    final context = await repository.olderMessageCursor(
      conversationId: conversationId,
      before: cursor,
      count: pageSize,
    );
    if (_closed) return;
    _retarget(
      ConversationMessagesFrom(switch (context) {
        Success(value: final below?) => below,
        _ => cursor,
      }),
    );
  }

  Future<void> dispose() async {
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _states.close();
  }

  StreamSubscription<ConversationMessagePage> _subscribe(
    ConversationMessageWindow window,
  ) {
    return repository
        .watchMessages(
          currentUserId: currentUserId,
          conversationId: conversationId,
          window: window,
        )
        .listen(
          _onPage,
          onError: (Object error, StackTrace stackTrace) {
            if (!_states.isClosed) _states.addError(error, stackTrace);
          },
        );
  }

  void _retarget(ConversationMessageWindow window) {
    if (_closed) return;
    _window = window;
    final previous = _subscription;
    _subscription = _subscribe(window);
    unawaited(previous?.cancel());
  }

  void _onPage(ConversationMessagePage page) {
    // An anchored window that comes back empty means its anchor is gone — a
    // message deleted for this device out from under the lower bound. Falling
    // back to the newest page is self-healing and costs one read; leaving it
    // would show an empty conversation that is not empty.
    if (page.messages.isEmpty && _window is ConversationMessagesFrom) {
      _retarget(NewestConversationMessages(pageSize));
      return;
    }
    _loadingBefore = false;
    _olderLoadFailed = false;
    _publish(page);
  }

  void _republish() {
    final page = _latest?.page;
    if (page != null) _publish(page);
  }

  void _publish(ConversationMessagePage page) {
    final state = ConversationTimelineState(
      page: page,
      loadingBefore: _loadingBefore,
      olderLoadFailed: _olderLoadFailed,
    );
    _latest = state;
    if (!_states.isClosed) _states.add(state);
  }
}
