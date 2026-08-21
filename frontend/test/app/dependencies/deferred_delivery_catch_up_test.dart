import 'dart:async';

import 'package:communication_platform/app/dependencies/deferred_delivery_catch_up.dart';
import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/application/reconcile_message_alerts.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a deferred catch-up refuses to do, and what it refuses to leave behind.
///
/// The composition itself needs a Keystore, a SQLCipher database and a native
/// cryptographic core, none of which a host test has. What a host test can
/// decide is every branch taken *before* any of that is touched, which is
/// exactly where the fail-closed decisions live.
void main() {
  Result<AccountSessionBoundary> restored({
    AccountSessionScope scope = AccountSessionScope.full,
    bool offline = false,
    bool securitySetupComplete = true,
    String? deviceId = 'device-1',
  }) => Result.success(
    AccountSessionBoundary(
      userId: 'user-1',
      deviceId: deviceId,
      scope: scope,
      offline: offline,
      securitySetupComplete: securitySetupComplete,
    ),
  );

  group('what a catch-up refuses to start', () {
    test('a full, set-up, device-bound, online session may proceed', () {
      expect(deferredCatchUpRefusal(restored()), isNull);
    });

    test('unreadable protected storage concludes nothing', () {
      // The device is locked after a restart and the credential-encrypted
      // database key cannot be unwrapped. There is no weaker path to fall back
      // to, and this must never be mistaken for "nothing was waiting".
      expect(
        deferredCatchUpRefusal(
          const Result.failure(StorageFailure(StorageFailureKind.unavailable)),
        ),
        DeferredCatchUpOutcome.storageUnavailable,
      );
    });

    test('an unreachable server is offline, not a lost session', () {
      expect(
        deferredCatchUpRefusal(
          const Result.failure(TransportFailure(TransportFailureKind.offline)),
        ),
        DeferredCatchUpOutcome.offline,
      );
    });

    test('a restore that fell back to the stored identity is offline', () {
      // `offline: true` means the access token could not be refreshed. There is
      // nothing to drain over a connection that is not there.
      expect(
        deferredCatchUpRefusal(restored(offline: true)),
        DeferredCatchUpOutcome.offline,
      );
    });

    test('an expired session has nobody to deliver to', () {
      expect(
        deferredCatchUpRefusal(
          const Result.failure(
            AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
          ),
        ),
        DeferredCatchUpOutcome.noSession,
      );
    });

    test('a register-scope session is not a session to deliver to', () {
      expect(
        deferredCatchUpRefusal(restored(scope: AccountSessionScope.register)),
        DeferredCatchUpOutcome.noSession,
      );
    });

    test(
      'an unfinished secure setup is the same bar the foreground applies',
      () {
        expect(
          deferredCatchUpRefusal(restored(securitySetupComplete: false)),
          DeferredCatchUpOutcome.noSession,
        );
      },
    );

    test('a session with no device identity cannot be scoped', () {
      expect(
        deferredCatchUpRefusal(restored(deviceId: null)),
        DeferredCatchUpOutcome.noSession,
      );
    });
  });

  group('when the wake-up stops happening', () {
    test('having nobody to deliver to disarms it', () {
      // Stable until the user signs in, and signing in is what arms it again.
      expect(deferredCatchUpDisarms(DeferredCatchUpOutcome.noSession), isTrue);
      expect(
        deferredCatchUpDisarms(DeferredCatchUpOutcome.unprovisioned),
        isTrue,
      );
    });

    test('a locked phone or a dropped connection does not', () {
      // Disarming on either would turn one bad moment into a permanent end of
      // background delivery, which no later event would undo.
      for (final outcome in const [
        DeferredCatchUpOutcome.storageUnavailable,
        DeferredCatchUpOutcome.offline,
        DeferredCatchUpOutcome.cycleFailed,
        DeferredCatchUpOutcome.delivered,
      ]) {
        expect(deferredCatchUpDisarms(outcome), isFalse, reason: '$outcome');
      }
    });
  });

  group('what a catch-up may do to the user', () {
    test('it never spends the one automatic permission prompt', () async {
      // ADR-048 asks for the notification permission at the point of use, once
      // for the lifetime of the install, and only while an activity is in front
      // of the user. A headless run has no activity, so reporting that truthful
      // background state is what keeps it from burning the single prompt into a
      // dialog nobody would ever see.
      final store = _FakeAlertStore()..pending.add('m1');
      final presenter = _FakePresenter(
        state: const MessageAlertPlatformState(
          enabled: false,
          runtimePermission: true,
          rationale: true,
        ),
      );

      final outcome = await ReconcileMessageAlerts(
        store: store,
        presenter: presenter,
        visible: const BackgroundVisibleConversation(),
        clock: const _FixedClock(),
      ).call(alertPosted: false);

      expect(presenter.requests, 0);
      expect(outcome.requested, isFalse);
      expect(
        store.alerted,
        isEmpty,
        reason:
            'nothing that could not be announced spends its marker, so a later '
            'grant announces the backlog instead of losing it',
      );
    });

    test('it does announce what it committed when it may', () async {
      final store = _FakeAlertStore()..pending.add('m1');
      final presenter = _FakePresenter();

      final outcome = await ReconcileMessageAlerts(
        store: store,
        presenter: presenter,
        visible: const BackgroundVisibleConversation(),
        clock: const _FixedClock(),
      ).call(alertPosted: false);

      expect(outcome.shown, isTrue);
      expect(presenter.shown, [MessageAlertBody.oneMessage]);
      expect(store.alerted, {'m1'});
    });

    test('nothing is on screen and nothing is in the foreground', () {
      const visible = BackgroundVisibleConversation();

      expect(visible.conversationId, isNull);
      expect(visible.isForeground, isFalse);
      expect(visible.changes, emitsDone);
    });
  });
}

final class _FixedClock implements TimeSource {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 8, 21, 12);
}

final class _FakeAlertStore implements MessageAlertStorePort {
  final List<String> pending = [];
  final Set<String> alerted = {};
  bool permissionRequested = false;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<Result<List<PendingMessageAlert>>> readPending({
    required int limit,
  }) async => Result.success([
    for (final id in pending.take(limit))
      PendingMessageAlert(
        messageId: id,
        conversationId: 'conversation-1',
        alerted: alerted.contains(id),
        mutedUntil: null,
      ),
  ]);

  @override
  Future<Result<void>> markAlerted(List<String> messageIds) async {
    alerted.addAll(messageIds);
    return const Result.success(null);
  }

  @override
  Future<Result<bool>> readPermissionRequested() async =>
      Result.success(permissionRequested);

  @override
  Future<Result<void>> recordPermissionRequested() async {
    permissionRequested = true;
    return const Result.success(null);
  }
}

final class _FakePresenter implements MessageAlertPresenterPort {
  _FakePresenter({
    this.state = const MessageAlertPlatformState(
      enabled: true,
      runtimePermission: true,
      rationale: false,
    ),
  });

  final MessageAlertPlatformState state;
  final List<MessageAlertBody> shown = [];
  int requests = 0;

  @override
  Future<MessageAlertPlatformState?> platformState() async => state;

  @override
  Future<MessageAlertPlatformState?> requestPermission() async {
    requests += 1;
    return state;
  }

  @override
  Future<void> show(MessageAlertBody body) async => shown.add(body);

  @override
  Future<void> hide() async {}

  @override
  Future<void> openSystemSettings() async {}
}
