import 'package:communication_platform/core/application/use_case.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/application/ports/authentication_ports.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';

final class AuthenticationUseCases {
  const AuthenticationUseCases({
    required this.register,
    required this.login,
    required this.restore,
    required this.logout,
    required this.lifecycle,
  });

  final RegisterAccount register;
  final LoginAccount login;
  final RestoreAccountSession restore;
  final LogoutAccount logout;
  final AuthenticationLifecyclePort lifecycle;
}

final class RegisterAccountInput {
  const RegisterAccountInput({required this.username, required this.password});

  final String username;
  final String password;
}

final class LoginAccountInput {
  const LoginAccountInput({required this.username, required this.password});

  final String username;
  final String password;
}

final class RegisterAccount
    implements UseCase<AccountRegistration, RegisterAccountInput> {
  const RegisterAccount(this.repository, {this.enrollmentMarker});

  final AccountAuthenticationRepository repository;
  final NewAccountEnrollmentMarkerPort? enrollmentMarker;

  Future<Result<AccountRegistration>> call({
    required String username,
    required String password,
  }) => execute(RegisterAccountInput(username: username, password: password));

  @override
  Future<Result<AccountRegistration>> execute(
    RegisterAccountInput input,
  ) async {
    final username = input.username;
    final password = input.password;
    final normalized = AuthenticationInputPolicy.normalizeUsername(username);
    if (!AuthenticationInputPolicy.isUsernameValid(normalized) ||
        !AuthenticationInputPolicy.isPasswordValid(password)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final result = await repository.register(
      username: normalized,
      password: password,
    );
    if (result case Success(value: final registration)) {
      final marker = enrollmentMarker;
      if (marker != null) {
        final marked = await marker.markNewAccount(userId: registration.userId);
        if (marked case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
      }
    }
    return result;
  }
}

final class LoginAccount
    implements UseCase<AccountSessionBoundary, LoginAccountInput> {
  const LoginAccount(this.repository, this.session);

  final AccountAuthenticationRepository repository;
  final AuthenticationSessionPort session;

  Future<Result<AccountSessionBoundary>> call({
    required String username,
    required String password,
  }) => execute(LoginAccountInput(username: username, password: password));

  @override
  Future<Result<AccountSessionBoundary>> execute(
    LoginAccountInput input,
  ) async {
    final username = input.username;
    final password = input.password;
    final normalized = AuthenticationInputPolicy.normalizeUsername(username);
    if (!AuthenticationInputPolicy.isUsernameValid(normalized) ||
        !AuthenticationInputPolicy.isPasswordValid(password)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }

    final hint = await session.readLoginHint();
    final deviceId = hint.appliesTo(normalized) ? hint.deviceId : null;
    final result = await repository.login(
      username: normalized,
      password: password,
      deviceId: deviceId,
    );
    switch (result) {
      case FailureResult(failure: final failure):
        return Result.failure(failure);
      case Success(value: final grant):
        return session.acceptLogin(
          username: normalized,
          grant: grant,
          replacedKnownDevice:
              deviceId != null && grant.scope == AccountSessionScope.register,
        );
    }
  }
}

final class RestoreAccountSession
    implements UseCase<AccountSessionBoundary, NoInput> {
  const RestoreAccountSession(this.session);

  final AuthenticationSessionPort session;

  Future<Result<AccountSessionBoundary>> call() => session.restore();

  @override
  Future<Result<AccountSessionBoundary>> execute(NoInput input) => call();
}

final class LogoutAccount implements UseCase<void, NoInput> {
  const LogoutAccount(this.session);

  final AuthenticationSessionPort session;

  Future<void> call() => session.logout();

  @override
  Future<Result<void>> execute(NoInput input) async {
    await call();
    return const Result.success(null);
  }
}
