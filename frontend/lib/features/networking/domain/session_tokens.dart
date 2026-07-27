/// Authentication scope encoded by the backend access token.
enum SessionScope { register, full }

/// Secret-bearing access material. This class deliberately has no custom string form.
final class AccessToken {
  const AccessToken({
    required this.value,
    required this.expiresAt,
    required this.scope,
  });

  final String value;
  final DateTime expiresAt;
  final SessionScope scope;
}

/// A rotating device session. Register-scope login tokens have no refresh token.
final class SessionTokens {
  const SessionTokens({required this.accessToken, this.refreshToken});

  final AccessToken accessToken;
  final String? refreshToken;

  bool get canRefresh =>
      accessToken.scope == SessionScope.full && refreshToken != null;
}

enum SessionTerminationReason { logout, revoked, refreshRejected, expired }
