// ignore_for_file: prefer_initializing_formals

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
    this.rotationRepairAttempts = 40,
    this.rotationRepairInterval = const Duration(milliseconds: 25),
    Future<void> Function(Duration) delay = _sleep,
  }) : _delay = delay;

  static Future<void> _sleep(Duration duration) =>
      Future<void>.delayed(duration);

  final SessionTokenStore store;
  final RefreshTokenExchange refreshExchange;
  final LogoutTokenExchange? logoutExchange;
  final SessionTerminationHandler terminationHandler;
  final TimeSource timeSource;
  final Duration proactiveRefreshWindow;
  final Duration clockSkewAllowance;

  /// How many times, and how far apart, a refresh that lost a race re-reads the
  /// shared durable row before it concludes that nobody else rotated.
  ///
  /// This exists because losing is observed *before* winning is persisted. The
  /// winner is told by the server, travels back over the same network, and only
  /// then writes the new pair to an encrypted local database; the loser's 401
  /// can easily arrive first. Without a bounded wait the loser would read a row
  /// that has not moved yet and end a session that is about to be repaired.
  ///
  /// The ceiling — attempts times interval — is what a genuinely ended session
  /// costs before the user is signed out, which is a second at the default. It
  /// is bounded by a count rather than by elapsed time on purpose: a device
  /// clock can move backwards, and a wait that cannot terminate is exactly the
  /// failure this whole piece exists to avoid.
  final int rotationRepairAttempts;
  final Duration rotationRepairInterval;

  final Future<void> Function(Duration) _delay;

  /// How many times one refresh may follow a token another owner rotated.
  ///
  /// Bounded so that two owners refreshing in lockstep cannot become an
  /// unbounded rotation chase against the backend's `refresh` throttle. Running
  /// out is not a session ending — see [_performRefresh] — so this number is a
  /// budget, not a safety property.
  static const _maximumAdoptions = 3;

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
    int generation, {
    int adoptionsLeft = _maximumAdoptions,
  }) async {
    final result = await refreshExchange.rotate(refreshToken);
    switch (result) {
      case Success(value: final tokens):
        if (generation != _sessionGeneration) {
          return const Result.failure(
            AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
          );
        }
        // Against the durable row rather than this isolate's cache: the row is
        // shared with every other delivery owner in this process, and a cached
        // answer would let a rotation overwrite a newer pair somebody else
        // persisted while this one was in flight. A row that cannot be read is
        // not evidence of anything, so the write is still attempted: the pair
        // just issued is the only one that works, and failing to persist it
        // loses the session.
        final durable = await _durableRow();
        if (durable.readable && durable.refreshToken != refreshToken) {
          final current = await store.read();
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
        if (!_endsSession(failure)) {
          return Result.failure(failure);
        }
        if (_mayBeALostRotation(failure) && generation == _sessionGeneration) {
          // The backend blacklists a refresh token the moment it is rotated,
          // so "this token is not valid" is what *both* a real session ending
          // and a lost race look like. They are told apart by the durable row:
          // if it no longer holds the token just presented, another owner in
          // this process rotated first and this failure is the consequence of
          // that, not of the server ending the session. Adopting what it wrote
          // is the repair; ending the session here would sign out a user who
          // did nothing (ADR-050).
          final adopted = await _awaitRotationByAnotherOwner(refreshToken);
          if (adopted != null && generation == _sessionGeneration) {
            if (adoptionsLeft > 0) {
              return _performRefresh(
                adopted,
                generation,
                adoptionsLeft: adoptionsLeft - 1,
              );
            }
            // Out of budget, but the row moved again: another owner is rotating
            // in lockstep with this one, which is positive evidence that the
            // session is *alive*. Ending it here would be the one outcome that
            // cannot be undone, so this is reported as the transient thing it
            // is and the next call starts again from whatever the row holds by
            // then.
            return const Result.failure(
              TransportFailure(TransportFailureKind.timeout),
            );
          }
        }
        final reason =
            failure is BackendFailure &&
                failure.code == BackendFailureCode.tokenRevoked
            ? SessionTerminationReason.revoked
            : SessionTerminationReason.refreshRejected;
        await _terminate(reason);
        return Result.failure(failure);
    }
  }

  /// Waits, briefly and finitely, for another owner in this process to publish
  /// the token it rotated — and answers null when none does.
  ///
  /// Null is the honest answer in exactly two situations, and both of them mean
  /// the same thing: the session is over. Either no other owner ever held this
  /// token, or one did, obtained a replacement, and stopped existing before it
  /// could persist it — in which case that replacement is lost and nothing can
  /// recover the session. Ending it is then correct rather than merely safe.
  Future<String?> _awaitRotationByAnotherOwner(String presented) async {
    for (var attempt = 0; ; attempt += 1) {
      final current = await _durableRow();
      if (current.readable &&
          current.refreshToken != null &&
          current.refreshToken != presented) {
        return current.refreshToken;
      }
      if (attempt >= rotationRepairAttempts) {
        return null;
      }
      await _delay(rotationRepairInterval);
    }
  }

  /// What the shared durable store holds right now, and whether it could be
  /// asked at all.
  ///
  /// The two are kept apart deliberately. A store that cannot be read is never
  /// mistaken for one that holds nothing, and never for one somebody else has
  /// rotated: an unanswerable question is not evidence, and reading it as
  /// either would be a way of ending a session that is alive, or of never
  /// ending one that is not.
  Future<({bool readable, String? refreshToken})> _durableRow() async {
    try {
      return (
        readable: true,
        refreshToken: (await store.readDurable())?.refreshToken,
      );
    } on Object {
      return (readable: false, refreshToken: null);
    }
  }

  /// Whether this failure is one a *blacklisted* refresh token produces.
  ///
  /// `POST /api/v1/auth/refresh` answers `invalid_token` for a token that is
  /// missing, malformed, expired or already rotated — the last of which is what
  /// losing a race looks like. `token_revoked` is a different answer with a
  /// different meaning: a revoked or deleted device, a stale token generation,
  /// or a deactivated account. None of those is repaired by presenting a
  /// different token, so that one ends the session immediately.
  bool _mayBeALostRotation(Failure failure) => switch (failure) {
    BackendFailure(
      code: BackendFailureCode.invalidToken || BackendFailureCode.tokenNotValid,
    ) =>
      true,
    _ => false,
  };

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
