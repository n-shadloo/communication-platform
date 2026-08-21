import 'dart:async';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/application/reconcile_message_alerts.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole policy, in one place and with no platform under it.
///
/// Every question this piece has to answer - is the same message announced
/// twice, does a restart repeat it, does a conversation on screen stay silent,
/// what happens when the user reads on another device, what happens when
/// permission is refused - is decided here, so all of them are decided by a
/// host test rather than by a device nobody has.
void main() {
  group('what gets announced', () {
    test('an arrived message is announced once', () async {
      final harness = AlertHarness()..arrive('m1');

      expect((await harness.reconcile()).shown, isTrue);
      expect(harness.presenter.shown, [MessageAlertBody.oneMessage]);
      expect(harness.store.alerted, {'m1'});
    });

    test('observing the same message again announces nothing', () async {
      final harness = AlertHarness()..arrive('m1');
      await harness.reconcile();

      // A re-drain re-observes a row that is still unread. The durable marker,
      // not memory, is what makes the second look a no-op.
      final outcome = await harness.reconcile();

      expect(outcome.shown, isFalse);
      expect(harness.presenter.shown, hasLength(1));
    });

    test('a restart does not repeat an announcement', () async {
      final harness = AlertHarness()..arrive('m1');
      await harness.reconcile();
      harness.restartProcess();

      final outcome = await harness.reconcile();

      expect(
        outcome.shown,
        isFalse,
        reason:
            'the isolate that announced it is gone; only the durable marker '
            'survives, and it is what has to be sufficient',
      );
    });

    test('grammatical number follows what is actually outstanding', () async {
      final harness = AlertHarness()
        ..arrive('m1')
        ..arrive('m2');

      expect((await harness.reconcile()).body, MessageAlertBody.manyMessages);
    });

    test('a second wave re-announces without repeating the first', () async {
      final harness = AlertHarness()..arrive('m1');
      await harness.reconcile();
      harness.arrive('m2');

      final outcome = await harness.reconcile();

      expect(outcome.shown, isTrue);
      expect(outcome.body, MessageAlertBody.manyMessages);
      expect(harness.store.alerted, {'m1', 'm2'});
    });
  });

  group('what stays silent', () {
    test(
      'a message in the conversation on screen is never announced',
      () async {
        final harness = AlertHarness()
          ..visible.conversationId = 'c1'
          ..arrive('m1', conversationId: 'c1');

        final outcome = await harness.reconcile();

        expect(outcome.shown, isFalse);
        expect(
          harness.store.alerted,
          {'m1'},
          reason:
              'the marker is spent anyway; leaving the conversation later must '
              'not announce something the user has already been shown',
        );
      },
    );

    test('leaving that conversation does not announce it afterwards', () async {
      final harness = AlertHarness()
        ..visible.conversationId = 'c1'
        ..arrive('m1', conversationId: 'c1');
      await harness.reconcile();

      harness.visible.conversationId = null;

      expect((await harness.reconcile()).shown, isFalse);
      expect(harness.presenter.shown, isEmpty);
    });

    test('a conversation on screen does not silence a different one', () async {
      final harness = AlertHarness()
        ..visible.conversationId = 'c1'
        ..arrive('m1', conversationId: 'c1')
        ..arrive('m2', conversationId: 'c2');

      final outcome = await harness.reconcile();

      expect(outcome.shown, isTrue);
      expect(
        outcome.body,
        MessageAlertBody.oneMessage,
        reason: 'the message on screen is not something still waiting',
      );
    });

    test('a backgrounded application is nobody looking at anything', () async {
      final harness = AlertHarness()
        ..visible.conversationId = 'c1'
        ..visible.isForeground = false
        ..arrive('m1', conversationId: 'c1');

      // The route is still mounted. The user is not there.
      expect((await harness.reconcile()).shown, isTrue);
    });

    test(
      'a muted conversation is announced and marked, never announced',
      () async {
        final harness = AlertHarness()
          ..arrive('m1', conversationId: 'c1', mutedUntil: hour(3));

        final outcome = await harness.reconcile();

        expect(outcome.shown, isFalse);
        expect(
          harness.store.alerted,
          {'m1'},
          reason: 'outliving the mute must not turn into a late announcement',
        );
      },
    );

    test('an expired mute stops silencing anything', () async {
      final harness = AlertHarness()
        ..arrive('m1', conversationId: 'c1', mutedUntil: hour(-1));

      expect((await harness.reconcile()).shown, isTrue);
    });
  });

  group('withdrawing', () {
    test('reading everywhere withdraws the alert', () async {
      final harness = AlertHarness()..arrive('m1');
      await harness.reconcile();

      // What marking the conversation read does, and what a read receipt from
      // the user's other device does through the projector: the row stops
      // being unread.
      harness.store.pending.clear();
      final outcome = await harness.reconcile();

      expect(outcome.hidden, isTrue);
      expect(harness.presenter.hidden, 1);
    });

    test('a withdrawn message stops being something outstanding', () async {
      final harness = AlertHarness()..arrive('m1');
      await harness.reconcile();

      // A delete-for-everyone rebuild leaves the row unread with no content.
      // The store never offers it again, and the alert follows.
      harness.store.pending.clear();
      await harness.reconcile();

      expect(harness.presenter.hidden, 1);
    });

    test('the first pass of a session withdraws a stale alert', () async {
      // A previous process announced something, was killed, and the user read
      // it on another device meanwhile. Nothing in this process knows the shade
      // is holding an alert, so the first pass has to assume it might be.
      final harness = AlertHarness();

      final outcome = await harness.reconcile();

      expect(outcome.hidden, isTrue);
      expect(harness.presenter.hidden, 1);
    });

    test('an empty pass does not withdraw what is not there', () async {
      final harness = AlertHarness();
      await harness.reconcile();

      await harness.reconcile();

      expect(harness.presenter.hidden, 1);
    });
  });

  group('permission', () {
    test('nothing is announced and no marker is spent without it', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: true,
        )
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.shown, isFalse);
      expect(outcome.authorization, MessageAlertAuthorization.withheld);
      expect(
        harness.store.alerted,
        isEmpty,
        reason:
            'what could not be announced stays eligible, so granting later '
            'announces the backlog instead of losing it',
      );
    });

    test('granting later announces the backlog', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: true,
        )
        ..arrive('m1');
      await harness.reconcile();

      harness.presenter.state = const MessageAlertPlatformState(
        enabled: true,
        runtimePermission: true,
        rationale: false,
      );

      expect((await harness.reconcile()).shown, isTrue);
    });

    test('the automatic prompt is spent once, at the point of use', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        )
        ..presenter.grantOnRequest = true
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.requested, isTrue);
      expect(outcome.shown, isTrue);
      expect(harness.store.permissionRequested, isTrue);
    });

    test('a refusal is not asked about again', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        )
        ..arrive('m1');
      expect((await harness.reconcile()).requested, isTrue);

      harness.arrive('m2');
      final outcome = await harness.reconcile();

      expect(
        outcome.requested,
        isFalse,
        reason:
            'Android treats a second refusal as permanent, and this app '
            'does not nag',
      );
      expect(harness.presenter.requests, 1);
    });

    test('a refusal made in Settings is respected without a marker', () async {
      // Settings writes no durable marker: the user asked for the prompt there,
      // and refused. Android reporting a rationale is what tells the automatic
      // prompt to stay out of it.
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: true,
        )
        ..arrive('m1');

      expect((await harness.reconcile()).requested, isFalse);
      expect(harness.presenter.requests, 0);
    });

    test('the prompt waits for an activity the user is looking at', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        )
        ..visible.isForeground = false
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.requested, isFalse);
      expect(harness.store.permissionRequested, isFalse);
      expect(harness.store.alerted, isEmpty);
    });

    test(
      'notifications switched off below Android 13 are not askable',
      () async {
        final harness = AlertHarness()
          ..presenter.state = const MessageAlertPlatformState(
            enabled: false,
            runtimePermission: false,
            rationale: false,
          )
          ..arrive('m1');

        final outcome = await harness.reconcile();

        expect(outcome.authorization, MessageAlertAuthorization.withheld);
        expect(harness.presenter.requests, 0);
      },
    );
  });

  group('failing safely', () {
    test('no platform implementation announces nothing', () async {
      final harness = AlertHarness()
        ..presenter.state = null
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.authorization, MessageAlertAuthorization.unavailable);
      expect(outcome.shown, isFalse);
      expect(harness.store.alerted, isEmpty);
    });

    test('a throwing platform announces nothing and spends nothing', () async {
      final harness = AlertHarness()
        ..presenter.throwOnEverything = true
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.shown, isFalse);
      expect(harness.store.alerted, isEmpty);
    });

    test('a post that fails does not spend the marker', () async {
      final harness = AlertHarness()
        ..presenter.throwOnShow = true
        ..arrive('m1');

      final outcome = await harness.reconcile();

      expect(outcome.shown, isFalse);
      expect(
        harness.store.alerted,
        isEmpty,
        reason: 'a marker spent on an alert nobody saw is a lost message',
      );
    });

    test('unreadable storage concludes nothing at all', () async {
      final harness = AlertHarness()
        ..arrive('m1')
        ..store.failReads = true;

      final outcome = await harness.reconcile();

      expect(outcome.shown, isFalse);
      expect(outcome.hidden, isFalse);
      expect(harness.presenter.shown, isEmpty);
      expect(harness.presenter.hidden, 0);
    });

    test('an unreadable prompt marker withholds the prompt', () async {
      final harness = AlertHarness()
        ..presenter.state = const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: false,
        )
        ..store.failPreferenceReads = true
        ..arrive('m1');

      expect((await harness.reconcile()).requested, isFalse);
    });
  });

  group('after a long absence', () {
    test('two hundred messages are one alert', () async {
      final harness = AlertHarness();
      for (var index = 0; index < 200; index += 1) {
        harness.arrive('m$index', conversationId: 'c${index % 12}');
      }

      final outcome = await harness.reconcile();

      expect(harness.presenter.shown, hasLength(1));
      expect(outcome.body, MessageAlertBody.manyMessages);
    });

    test('the read is bounded and still spends every marker it read', () async {
      final harness = AlertHarness(limit: 4);
      for (var index = 0; index < 10; index += 1) {
        harness.arrive('m$index');
      }

      await harness.reconcile();

      expect(harness.store.alerted, hasLength(4));
      // The rest are still fresh, and the next pass takes the next batch. No
      // message is skipped and no message is announced twice.
      await harness.reconcile();
      expect(harness.store.alerted, hasLength(8));
    });
  });
}

DateTime hour(int offset) =>
    DateTime.utc(2026, 8, 21, 12).add(Duration(hours: offset));

final class AlertHarness {
  AlertHarness({int limit = 256})
    : store = FakeAlertStore(),
      presenter = FakeAlertPresenter(),
      visible = FakeVisibleConversation() {
    reconciler = ReconcileMessageAlerts(
      store: store,
      presenter: presenter,
      visible: visible,
      clock: FixedClock(),
      limit: limit,
    );
  }

  final FakeAlertStore store;
  final FakeAlertPresenter presenter;
  final FakeVisibleConversation visible;
  late final ReconcileMessageAlerts reconciler;

  /// What the controller tracks across passes.
  bool alertPosted = true;

  void arrive(
    String messageId, {
    String conversationId = 'c1',
    DateTime? mutedUntil,
  }) {
    store.pending.add(
      PendingMessageAlert(
        messageId: messageId,
        conversationId: conversationId,
        alerted: false,
        mutedUntil: mutedUntil,
      ),
    );
  }

  /// Everything volatile is lost; the database is not.
  void restartProcess() {
    presenter.shown.clear();
    presenter.hidden = 0;
    alertPosted = true;
  }

  Future<MessageAlertOutcome> reconcile() async {
    final outcome = await reconciler.call(alertPosted: alertPosted);
    if (outcome.shown) {
      alertPosted = true;
    } else if (outcome.hidden) {
      alertPosted = false;
    }
    return outcome;
  }
}

final class FixedClock implements TimeSource {
  @override
  DateTime now() => DateTime.utc(2026, 8, 21, 12);
}

final class FakeAlertStore implements MessageAlertStorePort {
  final List<PendingMessageAlert> pending = [];
  final Set<String> alerted = {};
  // The reconciler under test never subscribes: it reads on demand, and the
  // controller owns the subscription. The stream only satisfies the port.
  // ignore: close_sinks
  final StreamController<void> _changes = StreamController<void>.broadcast();
  bool permissionRequested = false;
  bool failReads = false;
  bool failPreferenceReads = false;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<Result<List<PendingMessageAlert>>> readPending({
    required int limit,
  }) async {
    if (failReads) {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
    // The same ordering the Drift store uses: rows whose marker is unspent
    // first, so a bounded page always makes progress.
    final rows =
        pending
            .map(
              (message) => PendingMessageAlert(
                messageId: message.messageId,
                conversationId: message.conversationId,
                alerted: alerted.contains(message.messageId),
                mutedUntil: message.mutedUntil,
              ),
            )
            .toList()
          ..sort((left, right) {
            if (left.alerted == right.alerted) {
              return 0;
            }
            return left.alerted ? 1 : -1;
          });
    return Result.success(rows.take(limit).toList(growable: false));
  }

  @override
  Future<Result<void>> markAlerted(List<String> messageIds) async {
    alerted.addAll(messageIds);
    return const Result.success(null);
  }

  @override
  Future<Result<bool>> readPermissionRequested() async {
    if (failPreferenceReads) {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
    return Result.success(permissionRequested);
  }

  @override
  Future<Result<void>> recordPermissionRequested() async {
    permissionRequested = true;
    return const Result.success(null);
  }
}

final class FakeAlertPresenter implements MessageAlertPresenterPort {
  final List<MessageAlertBody> shown = [];
  int hidden = 0;
  int requests = 0;
  int settingsOpened = 0;
  bool grantOnRequest = false;
  bool throwOnShow = false;
  bool throwOnEverything = false;
  MessageAlertPlatformState? state = const MessageAlertPlatformState(
    enabled: true,
    runtimePermission: true,
    rationale: false,
  );

  @override
  Future<MessageAlertPlatformState?> platformState() async {
    if (throwOnEverything) {
      throw StateError('no platform');
    }
    return state;
  }

  @override
  Future<MessageAlertPlatformState?> requestPermission() async {
    requests += 1;
    if (grantOnRequest) {
      state = const MessageAlertPlatformState(
        enabled: true,
        runtimePermission: true,
        rationale: false,
      );
    }
    return state;
  }

  @override
  Future<void> show(MessageAlertBody body) async {
    if (throwOnShow || throwOnEverything) {
      throw StateError('cannot post');
    }
    shown.add(body);
  }

  @override
  Future<void> hide() async {
    hidden += 1;
  }

  @override
  Future<void> openSystemSettings() async {
    settingsOpened += 1;
  }
}

final class FakeVisibleConversation implements VisibleConversationPort {
  // ignore: close_sinks
  final StreamController<void> _changes = StreamController<void>.broadcast();
  String? _conversationId;

  @override
  bool isForeground = true;

  @override
  String? get conversationId => isForeground ? _conversationId : null;

  set conversationId(String? value) => _conversationId = value;

  @override
  Stream<void> get changes => _changes.stream;
}
