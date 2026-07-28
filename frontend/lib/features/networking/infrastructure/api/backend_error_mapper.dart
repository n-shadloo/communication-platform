import 'package:communication_platform/core/result/failure.dart';

BackendFailure mapBackendFailure({
  required int statusCode,
  required String? wireCode,
  Duration? retryAfter,
}) {
  if (statusCode == 429) {
    return BackendFailure(
      BackendFailureCode.rateLimited,
      retryAfter: retryAfter,
    );
  }
  final code = switch (wireCode) {
    'invalid_request' => BackendFailureCode.invalidRequest,
    'bad_request' => BackendFailureCode.badRequest,
    'username_taken' => BackendFailureCode.usernameTaken,
    'invalid_credentials' => BackendFailureCode.invalidCredentials,
    'account_inactive' => BackendFailureCode.accountInactive,
    'invalid_token' => BackendFailureCode.invalidToken,
    'token_not_valid' => BackendFailureCode.tokenNotValid,
    'token_revoked' => BackendFailureCode.tokenRevoked,
    'scope_forbidden' => BackendFailureCode.scopeForbidden,
    'device_scope_required' => BackendFailureCode.deviceScopeRequired,
    'forbidden' => BackendFailureCode.forbidden,
    'not_found' => BackendFailureCode.notFound,
    'bad_bucket' => BackendFailureCode.badBucket,
    'stale_version' => BackendFailureCode.staleVersion,
    'identity_required' => BackendFailureCode.identityRequired,
    'device_limit' => BackendFailureCode.deviceLimit,
    'prekey_limit' => BackendFailureCode.prekeyLimit,
    'keypackage_limit' => BackendFailureCode.keypackageLimit,
    'quota_exceeded' => BackendFailureCode.quotaExceeded,
    'voice_unconfigured' => BackendFailureCode.voiceUnconfigured,
    _ when statusCode == 401 => BackendFailureCode.tokenNotValid,
    _ when statusCode == 403 => BackendFailureCode.forbidden,
    _ when statusCode == 404 => BackendFailureCode.notFound,
    _ when statusCode == 400 => BackendFailureCode.invalidRequest,
    _ => BackendFailureCode.unknown,
  };
  return BackendFailure(code);
}
