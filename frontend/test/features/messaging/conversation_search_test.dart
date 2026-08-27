import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/features/messaging/presentation/conversation_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-conversation search is local by construction: it is a filter over the
/// list a screen has already decrypted and mapped. There is no query object, no
/// port and no transport for one to travel through — which is what these tests
/// assert by exercising the only entry point there is.
void main() {
  final history = [
    _message('m1', 'Bring the blue folder tomorrow'),
    _message('m2', 'BLUE is the wrong word for it'),
    _message('m3', 'nothing relevant here'),
    _message('m4', null),
    _message('m5', 'یک پیام فارسی درباره پرونده'),
  ];

  test('matches are case-insensitive and keep conversation order', () {
    final matches = conversationSearchMatches(query: 'blue', messages: history);
    expect(matches.map((message) => message.id), ['m1', 'm2']);
  });

  test('a deleted or non-text message is skipped rather than crashing', () {
    expect(
      conversationSearchMatches(
        query: 'relevant',
        messages: history,
      ).map((message) => message.id),
      ['m3'],
    );
  });

  test('Persian text matches Persian queries', () {
    expect(
      conversationSearchMatches(
        query: 'پرونده',
        messages: history,
      ).map((message) => message.id),
      ['m5'],
    );
  });

  test('an empty or blank query matches nothing at all', () {
    for (final query in const ['', '   ', '\n']) {
      expect(
        conversationSearchMatches(query: query, messages: history),
        isEmpty,
        reason: 'query "$query"',
      );
    }
  });

  test('the whole loaded history is searched, not a recent window', () {
    // The scope this surface states is "everything loaded on this phone for
    // this conversation". `watchMessages` returns a window (ADR-062), so the
    // guarantee this filter can make is exactly this one: it reads every
    // element it is given, including the very first. What it is given is the
    // window, and a hit outside it is reached by paging back — the filter is
    // not what narrowed, the list is.
    final long = [
      _message('oldest', 'needle at the very beginning'),
      for (var index = 0; index < 50000; index += 1)
        _message('filler-$index', 'nothing'),
    ];
    expect(
      conversationSearchMatches(query: 'needle', messages: long).single.id,
      'oldest',
    );
  });

  test(
    'results stop at the stated limit rather than growing without bound',
    () {
      final many = [
        for (var index = 0; index < 200; index += 1)
          _message('m$index', 'repeated needle'),
      ];
      final matches = conversationSearchMatches(
        query: 'needle',
        messages: many,
      );
      expect(matches, hasLength(conversationSearchResultLimit));
      // The screen says so when this happens; a silently truncated result set
      // would be a search quietly misdescribing its own scope.
      expect(conversationSearchResultLimit, 30);
    },
  );

  test('the returned list cannot be mutated by a caller', () {
    final matches = conversationSearchMatches(query: 'blue', messages: history);
    expect(() => matches.add(history.first), throwsUnsupportedError);
  });
}

ChatMessageViewModel _message(String id, String? text) => ChatMessageViewModel(
  id: id,
  authorId: 'author',
  authorName: 'Author',
  outgoing: false,
  kind: ChatTimelineContentKind.text,
  text: text,
  timestamp: DateTime.utc(2026),
  delivery: ChatDeliveryViewState.delivered,
  firstInAuthorGroup: true,
  lastInAuthorGroup: true,
  edited: false,
  deleted: text == null,
  pinned: false,
  starred: false,
  unread: false,
  timestampSkewed: false,
  canEdit: false,
  canDeleteForEveryone: false,
);
