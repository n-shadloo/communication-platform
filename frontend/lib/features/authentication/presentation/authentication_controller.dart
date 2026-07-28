import 'dart:async';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/application/authentication_use_cases.dart';
import 'package:communication_platform/features/authentication/application/ports/authentication_ports.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthenticationRouteAccess {
  dormant,
  signedOut,
  pendingActivation,
  registerScope,
  secureSetup,
  fullScope,
  offlineFullScope,
}

enum AuthenticationOperation { idle, restoring, login, register, logout }

enum AuthenticationMessage {
  invalidCredentials,
  accountInactive,
  usernameTaken,
  rateLimited,
  offline,
  malformedResponse,
  invalidInput,
  sessionExpired,
  revoked,
  storageUnavailable,
  generic,
}

final class AuthenticationViewState {
  const AuthenticationViewState({
    required this.access,
    required this.operation,
    this.username,
    this.userId,
    this.message,
  });

  const AuthenticationViewState.dormant()
    : access = AuthenticationRouteAccess.dormant,
      operation = AuthenticationOperation.idle,
      username = null,
      userId = null,
      message = null;

  final AuthenticationRouteAccess access;
  final AuthenticationOperation operation;
  final String? username;
  final String? userId;
  final AuthenticationMessage? message;

  bool get isBusy => operation != AuthenticationOperation.idle;

  AuthenticationViewState copyWith({
    AuthenticationRouteAccess? access,
    AuthenticationOperation? operation,
    String? username,
    bool clearUsername = false,
    String? userId,
    bool clearUserId = false,
    AuthenticationMessage? message,
    bool clearMessage = false,
  }) => AuthenticationViewState(
    access: access ?? this.access,
    operation: operation ?? this.operation,
    username: clearUsername ? null : username ?? this.username,
    userId: clearUserId ? null : userId ?? this.userId,
    message: clearMessage ? null : message ?? this.message,
  );
}

final authenticationUseCasesProvider = Provider<AuthenticationUseCases>(
  (ref) => throw StateError('Authentication dependencies are not installed.'),
);

final authenticationControllerProvider =
    NotifierProvider<AuthenticationController, AuthenticationViewState>(
      AuthenticationController.new,
    );

final class AuthenticationController extends Notifier<AuthenticationViewState> {
  StreamSubscription<AuthenticationTermination>? _terminationSubscription;
  bool _restorationStarted = false;

  AuthenticationUseCases get _useCases =>
      ref.read(authenticationUseCasesProvider);

  @override
  AuthenticationViewState build() {
    _terminationSubscription = _useCases.lifecycle.terminations.listen(
      _onTermination,
    );
    ref.onDispose(() => _terminationSubscription?.cancel());
    return const AuthenticationViewState.dormant();
  }

  void enterSignedOut({String? rememberedUsername}) {
    if (state.access != AuthenticationRouteAccess.dormant) {
      return;
    }
    state = AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.idle,
      username: rememberedUsername,
    );
  }

  Future<void> restore() async {
    if (_restorationStarted) {
      return;
    }
    _restorationStarted = true;
    state = state.copyWith(
      operation: AuthenticationOperation.restoring,
      clearMessage: true,
    );
    final result = await _useCases.restore();
    switch (result) {
      case Success(value: final boundary):
        _applyBoundary(boundary);
      case FailureResult(failure: final failure):
        state = AuthenticationViewState(
          access: AuthenticationRouteAccess.signedOut,
          operation: AuthenticationOperation.idle,
          username: state.username,
          message: _messageFor(failure),
        );
    }
  }

  Future<bool> register({
    required String username,
    required String password,
  }) async {
    if (state.isBusy) {
      return false;
    }
    final normalized = AuthenticationInputPolicy.normalizeUsername(username);
    state = AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.register,
      username: normalized,
    );
    final result = await _useCases.register(
      username: normalized,
      password: password,
    );
    switch (result) {
      case Success():
        state = AuthenticationViewState(
          access: AuthenticationRouteAccess.pendingActivation,
          operation: AuthenticationOperation.idle,
          username: normalized,
        );
        return true;
      case FailureResult(failure: final failure):
        state = AuthenticationViewState(
          access: AuthenticationRouteAccess.signedOut,
          operation: AuthenticationOperation.idle,
          username: normalized,
          message: _messageFor(failure),
        );
        return false;
    }
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    if (state.isBusy) {
      return false;
    }
    final normalized = AuthenticationInputPolicy.normalizeUsername(username);
    state = AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.login,
      username: normalized,
    );
    final result = await _useCases.login(
      username: normalized,
      password: password,
    );
    switch (result) {
      case Success(value: final boundary):
        _applyBoundary(boundary);
        return true;
      case FailureResult(failure: final failure):
        if (failure is BackendFailure &&
            failure.code == BackendFailureCode.accountInactive) {
          state = AuthenticationViewState(
            access: AuthenticationRouteAccess.pendingActivation,
            operation: AuthenticationOperation.idle,
            username: normalized,
            message: AuthenticationMessage.accountInactive,
          );
        } else {
          state = AuthenticationViewState(
            access: AuthenticationRouteAccess.signedOut,
            operation: AuthenticationOperation.idle,
            username: normalized,
            message: _messageFor(failure),
          );
        }
        return false;
    }
  }

  void returnToLogin() {
    state = AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.idle,
      username: state.username,
    );
  }

  Future<void> logout() async {
    if (state.isBusy) {
      return;
    }
    state = state.copyWith(
      operation: AuthenticationOperation.logout,
      clearMessage: true,
    );
    await _useCases.logout();
    state = const AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.idle,
    );
  }

  void secureSetupCompleted() {
    if (state.access != AuthenticationRouteAccess.registerScope &&
        state.access != AuthenticationRouteAccess.secureSetup) {
      return;
    }
    state = state.copyWith(
      access: AuthenticationRouteAccess.fullScope,
      operation: AuthenticationOperation.idle,
      clearMessage: true,
    );
  }

  void _applyBoundary(AccountSessionBoundary boundary) {
    state = AuthenticationViewState(
      access: switch (boundary.scope) {
        AccountSessionScope.register => AuthenticationRouteAccess.registerScope,
        AccountSessionScope.full when !boundary.securitySetupComplete =>
          AuthenticationRouteAccess.secureSetup,
        AccountSessionScope.full when boundary.offline =>
          AuthenticationRouteAccess.offlineFullScope,
        AccountSessionScope.full => AuthenticationRouteAccess.fullScope,
      },
      operation: AuthenticationOperation.idle,
      username: state.username,
      userId: boundary.userId,
    );
  }

  void _onTermination(AuthenticationTermination termination) {
    state = AuthenticationViewState(
      access: AuthenticationRouteAccess.signedOut,
      operation: AuthenticationOperation.idle,
      username: termination == AuthenticationTermination.logout
          ? null
          : state.username,
      userId: null,
      message: switch (termination) {
        AuthenticationTermination.logout => null,
        AuthenticationTermination.revoked => AuthenticationMessage.revoked,
        AuthenticationTermination.expired =>
          AuthenticationMessage.sessionExpired,
      },
    );
  }

  AuthenticationMessage _messageFor(Failure failure) => switch (failure) {
    BackendFailure(code: BackendFailureCode.invalidCredentials) =>
      AuthenticationMessage.invalidCredentials,
    BackendFailure(code: BackendFailureCode.accountInactive) =>
      AuthenticationMessage.accountInactive,
    BackendFailure(code: BackendFailureCode.usernameTaken) =>
      AuthenticationMessage.usernameTaken,
    BackendFailure(code: BackendFailureCode.rateLimited) =>
      AuthenticationMessage.rateLimited,
    BackendFailure(code: BackendFailureCode.tokenRevoked) =>
      AuthenticationMessage.revoked,
    BackendFailure(
      code: BackendFailureCode.invalidToken || BackendFailureCode.tokenNotValid,
    ) =>
      AuthenticationMessage.sessionExpired,
    TransportFailure() => AuthenticationMessage.offline,
    SecurityFailure(kind: SecurityFailureKind.malformedServerResponse) =>
      AuthenticationMessage.malformedResponse,
    ValidationFailure() => AuthenticationMessage.invalidInput,
    StorageFailure() => AuthenticationMessage.storageUnavailable,
    AuthenticationFailure() => AuthenticationMessage.sessionExpired,
    _ => AuthenticationMessage.generic,
  };
}
