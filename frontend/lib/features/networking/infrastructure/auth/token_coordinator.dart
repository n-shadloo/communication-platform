import 'dart:async';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';

final class TokenCoordinator implements AccessTokenCoordinator {
  TokenCoordinator({
    required this.store,
    required this.refreshExchange,
    required this.terminationHandler,
    required this.timeSource,
    this.logoutExchange,
    this.proactiveRefreshWindow = const Duration(minutes: 2),
    this.clockSkewAllowance = const Duration(seconds: 30),
  });

  final SessionTokenStore store;
  final RefreshTokenExchange refreshExchange;
  final LogoutTokenExchange? logoutExchange;
  final SessionTerminationHandler terminationHandler;
  final TimeSource timeSource;
  final Duration proactiveRefreshWindow;
  final Duration clockSkewAllowance;

  Future<Result<AccessToken>>? _refreshInFlight;
  int _sessionGeneration = 0;

  @override
  Future<Result<AccessToken>> accessToken({bool forceRefresh = false}) async {
    final tokens = await store.read();
    if (tokens == null) {
      return const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      );
    }
    final refreshAt = tokens.accessToken.expiresAt.subtract(
      proactiveRefreshWindow + clockSkewAllowance,
    );
    if (!forceRefresh && timeSource.now().toUtc().isBefore(refreshAt)) {
      return Result.success(tokens.accessToken);
    }
    if (!tokens.canRefresh) {
      if (timeSource.now().toUtc().isBefore(
        tokens.accessToken.expiresAt.subtract(clockSkewAllowance),
      )) {
        return Result.success(tokens.accessToken);
      }
      await _terminate(SessionTerminationReason.expired);
      return const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      );
    }
    return _singleFlightRefresh(tokens.refreshToken!);
  }

  @override
  Future<Result<AccessToken>> recoverAfterUnauthorized(
    String rejectedToken,
  ) async {
    final current = await store.read();
    if (current == null) {
      return const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      );
    }
    if (current.accessToken.value != rejectedToken) {
      return Result.success(current.accessToken);
    }
    return accessToken(forceRefresh: true);
  }

  Future<Result<AccessToken>> _singleFlightRefresh(String refreshToken) {
    final existing = _refreshInFlight;
    if (existing != null) {
      return existing;
    }
    final refresh = _performRefresh(refreshToken, _sessionGeneration);
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<Result<AccessToken>> _performRefresh(
    String refreshToken,
    int generation,
  ) async {
    final result = await refreshExchange.rotate(refreshToken);
    switch (result) {
      case Success(value: final tokens):
        final current = await store.read();
        if (generation != _sessionGeneration) {
          return const Result.failure(
            AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
          );
        }
        if (current?.refreshToken != refreshToken) {
          if (current != null && current.accessToken.value.isNotEmpty) {
            return Result.success(current.accessToken);
          }
          return const Result.failure(
            AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
          );
        }
        await store.replace(tokens);
        return Result.success(tokens.accessToken);
      case FailureResult(failure: final failure):
        if (_endsSession(failure)) {
          final reason =
              failure is BackendFailure &&
                  failure.code == BackendFailureCode.tokenRevoked
              ? SessionTerminationReason.revoked
              : SessionTerminationReason.refreshRejected;
          await _terminate(reason);
        }
        return Result.failure(failure);
    }
  }

  bool _endsSession(Failure failure) => switch (failure) {
    BackendFailure(
      code: BackendFailureCode.invalidToken ||
          BackendFailureCode.tokenNotValid ||
          BackendFailureCode.tokenRevoked,
    ) =>
      true,
    AuthenticationFailure(kind: AuthenticationFailureKind.sessionExpired) =>
      true,
    _ => false,
  };

  @override
  Future<void> logout() async {
    _sessionGeneration += 1;
    final tokens = await store.read();
    try {
      if (tokens?.refreshToken case final String refreshToken) {
        await logoutExchange?.revoke(
          accessToken: tokens!.accessToken.value,
          refreshToken: refreshToken,
        );
      }
    } on Object {
      // Local logout and wipe are mandatory even when the server is unreachable.
    } finally {
      await _terminate(SessionTerminationReason.logout);
    }
  }

  @override
  Future<void> handleRevocation() {
    _sessionGeneration += 1;
    return _terminate(SessionTerminationReason.revoked);
  }

  Future<void> _terminate(SessionTerminationReason reason) async {
    if (reason != SessionTerminationReason.logout &&
        reason != SessionTerminationReason.revoked) {
      _sessionGeneration += 1;
    }
    await store.clear();
    await terminationHandler.terminate(reason);
  }
}
