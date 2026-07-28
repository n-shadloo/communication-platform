import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';

/// Protected token persistence. Replacing a rotated pair must be atomic.
abstract interface class SessionTokenStore implements Port {
  Future<SessionTokens?> read();

  Future<void> replace(SessionTokens tokens);

  Future<void> clear();
}

abstract interface class RefreshTokenExchange implements Port {
  Future<Result<SessionTokens>> rotate(String refreshToken);
}

abstract interface class LogoutTokenExchange implements Port {
  Future<void> revoke({
    required String accessToken,
    required String refreshToken,
  });
}

abstract interface class SessionTerminationHandler implements Port {
  Future<void> terminate(SessionTerminationReason reason);
}

abstract interface class AccessTokenCoordinator implements Port {
  Future<Result<AccessToken>> accessToken({bool forceRefresh = false});

  Future<Result<AccessToken>> recoverAfterUnauthorized(String rejectedToken);

  Future<void> logout();

  Future<void> handleRevocation();
}
