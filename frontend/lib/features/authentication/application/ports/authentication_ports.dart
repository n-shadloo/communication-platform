import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';

abstract interface class AccountAuthenticationRepository implements Port {
  Future<Result<AccountRegistration>> register({
    required String username,
    required String password,
  });

  Future<Result<AccountSessionGrant>> login({
    required String username,
    required String password,
    String? deviceId,
  });
}

abstract interface class AuthenticationSessionPort implements Port {
  Future<LoginHint> readLoginHint();

  Future<Result<AccountSessionBoundary>> acceptLogin({
    required String username,
    required AccountSessionGrant grant,
    required bool replacedKnownDevice,
  });

  Future<Result<AccountSessionBoundary>> restore();

  Future<void> logout();
}

enum AuthenticationTermination { logout, revoked, expired }

abstract interface class AuthenticationLifecyclePort implements Port {
  Stream<AuthenticationTermination> get terminations;
}
