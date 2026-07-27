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

  @override
  Future<void> clear() async {
    current = null;
  }

  @override
  Future<SessionTokens?> read() async => current;

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
