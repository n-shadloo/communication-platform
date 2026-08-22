import 'dart:async';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/token_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proactive concurrent refreshes rotate exactly once', () async {
    final store = MemoryTokenStore(
      session('old-access', 'old-refresh', DateTime.utc(2026, 7, 27, 12, 1)),
    );
    final exchange = ControlledRefreshExchange();
    final termination = RecordingTerminationHandler();
    final coordinator = TokenCoordinator(
      store: store,
      refreshExchange: exchange,
      terminationHandler: termination,
      timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
    );

    final requests = List.generate(20, (_) => coordinator.accessToken());
    await Future<void>.delayed(Duration.zero);
    expect(exchange.calls, 1);
    exchange.completer.complete(
      Result.success(
        session('new-access', 'new-refresh', DateTime.utc(2026, 7, 27, 13)),
      ),
    );
    final results = await Future.wait(requests);

    expect(results, everyElement(isA<Success<AccessToken>>()));
    expect(
      results.map((result) => (result as Success<AccessToken>).value.value),
      everyElement('new-access'),
    );
    expect(store.replacements, 1);
    expect(store.current?.refreshToken, 'new-refresh');
    expect(termination.reasons, isEmpty);
  });

  test(
    'unauthorized request reuses a token already refreshed by another race',
    () async {
      final store = MemoryTokenStore(
        session('new-access', 'new-refresh', DateTime.utc(2026, 7, 27, 13)),
      );
      final exchange = ControlledRefreshExchange();
      final coordinator = TokenCoordinator(
        store: store,
        refreshExchange: exchange,
        terminationHandler: RecordingTerminationHandler(),
        timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
      );

      final result = await coordinator.recoverAfterUnauthorized('old-access');
      expect((result as Success<AccessToken>).value.value, 'new-access');
      expect(exchange.calls, 0);
    },
  );

  test('rejected refresh clears and terminates the local session', () async {
    final store = MemoryTokenStore(
      session('old-access', 'old-refresh', DateTime.utc(2026, 7, 27, 11)),
    );
    final termination = RecordingTerminationHandler();
    final exchange = ImmediateRefreshExchange(
      const Result.failure(BackendFailure(BackendFailureCode.tokenRevoked)),
    );
    final coordinator = TokenCoordinator(
      store: store,
      refreshExchange: exchange,
      terminationHandler: termination,
      timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
    );

    final result = await coordinator.accessToken();
    expect(result, isA<FailureResult<AccessToken>>());
    expect(store.current, isNull);
    expect(termination.reasons, [SessionTerminationReason.revoked]);
  });

  test('logout wipes locally even when remote logout fails', () async {
    final store = MemoryTokenStore(
      session('old-access', 'old-refresh', DateTime.utc(2026, 7, 27, 13)),
    );
    final termination = RecordingTerminationHandler();
    final coordinator = TokenCoordinator(
      store: store,
      refreshExchange: ImmediateRefreshExchange(
        Result.success(
          session('unused', 'unused', DateTime.utc(2026, 7, 27, 14)),
        ),
      ),
      logoutExchange: const ThrowingLogoutExchange(),
      terminationHandler: termination,
      timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
    );

    await coordinator.logout();
    expect(store.current, isNull);
    expect(termination.reasons, [SessionTerminationReason.logout]);
  });

  test(
    'a refresh completing after logout cannot resurrect the session',
    () async {
      final store = MemoryTokenStore(
        session('old-access', 'old-refresh', DateTime.utc(2026, 7, 27, 11)),
      );
      final exchange = ControlledRefreshExchange();
      final coordinator = TokenCoordinator(
        store: store,
        refreshExchange: exchange,
        terminationHandler: RecordingTerminationHandler(),
        timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
      );

      final refresh = coordinator.accessToken();
      await Future<void>.delayed(Duration.zero);
      await coordinator.logout();
      exchange.completer.complete(
        Result.success(
          session('late-access', 'late-refresh', DateTime.utc(2026, 7, 27, 13)),
        ),
      );

      expect(await refresh, isA<FailureResult<AccessToken>>());
      expect(store.current, isNull);
      expect(store.replacements, 0);
    },
  );

  test('register-scope token cannot refresh and expires closed', () async {
    final store = MemoryTokenStore(
      SessionTokens(
        accessToken: AccessToken(
          value: 'register-access',
          expiresAt: DateTime.utc(2026, 7, 27, 11),
          scope: SessionScope.register,
        ),
      ),
    );
    final termination = RecordingTerminationHandler();
    final exchange = ControlledRefreshExchange();
    final coordinator = TokenCoordinator(
      store: store,
      refreshExchange: exchange,
      terminationHandler: termination,
      timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
    );

    final result = await coordinator.accessToken();
    expect(result, isA<FailureResult<AccessToken>>());
    expect(exchange.calls, 0);
    expect(termination.reasons, [SessionTerminationReason.expired]);
  });

  group('a refresh that lost a race to another owner in this process', () {
    // The unit-level half of ADR-050. Real contention over a real shared store
    // is proved in `delivery_owner_contention_test.dart`; what is decided here
    // is every branch of the repair, including the ones a race is a clumsy way
    // to reach.

    TokenCoordinator coordinatorFor(
      SessionTokenStore store,
      RefreshTokenExchange exchange,
      SessionTerminationHandler termination, {
      int repairAttempts = 4,
    }) => TokenCoordinator(
      store: store,
      refreshExchange: exchange,
      terminationHandler: termination,
      timeSource: FixedTimeSource(DateTime.utc(2026, 7, 27, 12)),
      rotationRepairAttempts: repairAttempts,
      rotationRepairInterval: Duration.zero,
      delay: (_) async {},
    );

    test('it adopts what the other owner published rather than ending', () async {
      final store = MemoryTokenStore(
        session('old-access', 'lost-refresh', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final termination = RecordingTerminationHandler();
      // The winner persists on the second look, which is what a local encrypted
      // write landing just after the loser's 401 looks like.
      final exchange = ScriptedRefreshExchange({
        'lost-refresh': const Result.failure(
          BackendFailure(BackendFailureCode.invalidToken),
        ),
        'winner-refresh': Result.success(
          session('repaired', 'newest-refresh', DateTime.utc(2026, 7, 27, 13)),
        ),
      });
      store.onDurableRead = (reads) {
        if (reads == 2) {
          store.current = session(
            '',
            'winner-refresh',
            DateTime.utc(2026, 7, 27, 13),
          );
        }
      };

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      expect((result as Success<AccessToken>).value.value, 'repaired');
      expect(termination.reasons, isEmpty);
      expect(exchange.presented, ['lost-refresh', 'winner-refresh']);
      expect(store.current?.refreshToken, 'newest-refresh');
    });

    test('a row that never moves is a session that really ended', () async {
      final store = MemoryTokenStore(
        session('old-access', 'dead-refresh', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final termination = RecordingTerminationHandler();
      final exchange = ScriptedRefreshExchange({
        'dead-refresh': const Result.failure(
          BackendFailure(BackendFailureCode.invalidToken),
        ),
      });

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      expect(result, isA<FailureResult<AccessToken>>());
      expect(termination.reasons, [SessionTerminationReason.refreshRejected]);
      expect(
        exchange.presented,
        ['dead-refresh'],
        reason: 'waiting is free; presenting the same dead token again is not',
      );
    });

    test('a revoked device is never repaired, only ended', () async {
      final store = MemoryTokenStore(
        session('old-access', 'revoked', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final termination = RecordingTerminationHandler();
      final exchange = ScriptedRefreshExchange({
        'revoked': const Result.failure(
          BackendFailure(BackendFailureCode.tokenRevoked),
        ),
      });
      // Even with another owner publishing a token, `token_revoked` means the
      // device or the account is gone. Presenting a different token cannot
      // change that answer, so it is not tried.
      store.onDurableRead = (_) => store.current = session(
        '',
        'someone-elses',
        DateTime.utc(2026, 7, 27, 13),
      );

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      expect(result, isA<FailureResult<AccessToken>>());
      expect(termination.reasons, [SessionTerminationReason.revoked]);
      expect(exchange.presented, ['revoked']);
    });

    test('an unreadable store still persists the pair just issued', () async {
      // Reading the row and writing it are different failures. A read that
      // cannot be answered is not evidence that somebody else rotated - but the
      // pair just issued is the only one that works now, so declining to
      // attempt the write would lose the session over a transient read.
      final store = MemoryTokenStore(
        session('old-access', 'refresh-0', DateTime.utc(2026, 7, 27, 12, 1)),
      )..durableReadThrows = true;
      final termination = RecordingTerminationHandler();
      final exchange = ScriptedRefreshExchange({
        'refresh-0': Result.success(
          session('new-access', 'refresh-1', DateTime.utc(2026, 7, 27, 13)),
        ),
      });

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      expect((result as Success<AccessToken>).value.value, 'new-access');
      expect(store.current?.refreshToken, 'refresh-1');
      expect(termination.reasons, isEmpty);
    });

    test('no contention costs one durable read and one rotation', () async {
      // The normal case. The repair path is on the failure branch only, so a
      // lone owner pays a single extra read of a local encrypted row per
      // rotation and nothing else.
      final store = MemoryTokenStore(
        session('old-access', 'refresh-0', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final exchange = ScriptedRefreshExchange({
        'refresh-0': Result.success(
          session('new-access', 'refresh-1', DateTime.utc(2026, 7, 27, 13)),
        ),
      });

      final result = await coordinatorFor(
        store,
        exchange,
        RecordingTerminationHandler(),
      ).accessToken();

      expect(result, isA<Success<AccessToken>>());
      expect(exchange.presented, ['refresh-0']);
      expect(store.durableReads, 1);
      expect(store.replacements, 1);
    });

    test('a store that cannot be read never adopts', () async {
      final store = MemoryTokenStore(
        session('old-access', 'unreadable', DateTime.utc(2026, 7, 27, 12, 1)),
      )..durableReadThrows = true;
      final termination = RecordingTerminationHandler();
      final exchange = ScriptedRefreshExchange({
        'unreadable': const Result.failure(
          BackendFailure(BackendFailureCode.invalidToken),
        ),
      });

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      // Fail closed: an unanswerable question is never read as "somebody else
      // rotated", because that would be a way of never ending a session.
      expect(result, isA<FailureResult<AccessToken>>());
      expect(termination.reasons, [SessionTerminationReason.refreshRejected]);
    });

    test('lockstep contention is transient, never a sign-out', () async {
      // Every look finds a token newer than the one just presented, and every
      // presentation loses. The budget runs out - and running out must not end
      // a session that the moving row is positive evidence is alive.
      final store = MemoryTokenStore(
        session('old-access', 'refresh-0', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final termination = RecordingTerminationHandler();
      final exchange = AlwaysLosesRefreshExchange();
      var issued = 0;
      store.onDurableRead = (_) => store.current = session(
        '',
        'refresh-${++issued}',
        DateTime.utc(2026, 7, 27, 13),
      );

      final result = await coordinatorFor(
        store,
        exchange,
        termination,
      ).accessToken();

      expect(
        (result as FailureResult<AccessToken>).failure,
        isA<TransportFailure>(),
        reason: 'try again, not sign out',
      );
      expect(termination.reasons, isEmpty);
      expect(store.current, isNotNull);
      expect(
        exchange.presented.length,
        lessThanOrEqualTo(5),
        reason: 'the chase against the refresh throttle is bounded',
      );
    });

    test('a logout during the wait wins over the repair', () async {
      final store = MemoryTokenStore(
        session('old-access', 'refresh-0', DateTime.utc(2026, 7, 27, 12, 1)),
      );
      final termination = RecordingTerminationHandler();
      final exchange = ScriptedRefreshExchange({
        'refresh-0': const Result.failure(
          BackendFailure(BackendFailureCode.invalidToken),
        ),
      });
      final coordinator = coordinatorFor(store, exchange, termination);
      store.onDurableRead = (reads) {
        if (reads == 2) {
          unawaited(coordinator.logout());
        }
      };

      final result = await coordinator.accessToken();

      expect(result, isA<FailureResult<AccessToken>>());
      expect(
        exchange.presented,
        ['refresh-0'],
        reason: 'a session the user ended is not repaired back into existence',
      );
    });
  });
}

final class ScriptedRefreshExchange implements RefreshTokenExchange {
  ScriptedRefreshExchange(this._answers);

  final Map<String, Result<SessionTokens>> _answers;
  final List<String> presented = [];

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async {
    presented.add(refreshToken);
    return _answers[refreshToken] ??
        const Result.failure(BackendFailure(BackendFailureCode.invalidToken));
  }
}

final class AlwaysLosesRefreshExchange implements RefreshTokenExchange {
  final List<String> presented = [];

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async {
    presented.add(refreshToken);
    return const Result.failure(
      BackendFailure(BackendFailureCode.invalidToken),
    );
  }
}

final class FixedTimeSource implements TimeSource {
  const FixedTimeSource(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class MemoryTokenStore implements SessionTokenStore {
  MemoryTokenStore(this.current);

  SessionTokens? current;
  int replacements = 0;
  int durableReads = 0;
  bool durableReadThrows = false;

  /// Called with the running durable-read count, so a test can move the shared
  /// row at an exact point - which is what another owner in this process does.
  void Function(int reads)? onDurableRead;

  @override
  Future<void> clear() async {
    current = null;
  }

  @override
  Future<SessionTokens?> read() async => current;

  @override
  Future<SessionTokens?> readDurable() async {
    durableReads += 1;
    if (durableReadThrows) {
      throw StateError('Protected session storage is unavailable.');
    }
    onDurableRead?.call(durableReads);
    return current;
  }

  @override
  Future<void> replace(SessionTokens tokens) async {
    current = tokens;
    replacements += 1;
  }
}

final class ControlledRefreshExchange implements RefreshTokenExchange {
  final Completer<Result<SessionTokens>> completer = Completer();
  int calls = 0;

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) {
    calls += 1;
    return completer.future;
  }
}

final class ImmediateRefreshExchange implements RefreshTokenExchange {
  const ImmediateRefreshExchange(this.result);

  final Result<SessionTokens> result;

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async => result;
}

final class RecordingTerminationHandler implements SessionTerminationHandler {
  final List<SessionTerminationReason> reasons = [];

  @override
  Future<void> terminate(SessionTerminationReason reason) async {
    reasons.add(reason);
  }
}

final class ThrowingLogoutExchange implements LogoutTokenExchange {
  const ThrowingLogoutExchange();

  @override
  Future<void> revoke({
    required String accessToken,
    required String refreshToken,
  }) => throw StateError('offline');
}

SessionTokens session(String access, String refresh, DateTime expiresAt) =>
    SessionTokens(
      accessToken: AccessToken(
        value: access,
        expiresAt: expiresAt,
        scope: SessionScope.full,
      ),
      refreshToken: refresh,
    );
