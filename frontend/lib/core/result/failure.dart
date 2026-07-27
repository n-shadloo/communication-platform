/// Failure groups that presentation can map to reviewed, localized copy.
///
/// These types deliberately carry stable classifications only. Raw backend response
/// messages, server payloads, and exception text must remain in infrastructure logs
/// with redaction and must never cross this boundary.
sealed class Failure {
  const Failure();

  FailureCategory get category;
}

enum FailureCategory {
  transport,
  authentication,
  validation,
  security,
  storage,
  unsupportedProtocol,
  cancellation,
}

final class TransportFailure extends Failure {
  const TransportFailure(this.kind);

  final TransportFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.transport;
}

enum TransportFailureKind { offline, timeout, connectionRejected }

final class AuthenticationFailure extends Failure {
  const AuthenticationFailure(this.kind);

  final AuthenticationFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.authentication;
}

enum AuthenticationFailureKind { sessionExpired, accessDenied }

final class ValidationFailure extends Failure {
  const ValidationFailure(this.kind);

  final ValidationFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.validation;
}

enum ValidationFailureKind { invalidInput, conflict, limitExceeded }

final class SecurityFailure extends Failure {
  const SecurityFailure(this.kind);

  final SecurityFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.security;
}

enum SecurityFailureKind {
  unauthenticatedInput,
  integrityCheckFailed,
  policyBlocked,
}

final class StorageFailure extends Failure {
  const StorageFailure(this.kind);

  final StorageFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.storage;
}

enum StorageFailureKind { unavailable, migrationBlocked, capacityExceeded }

final class UnsupportedProtocolFailure extends Failure {
  const UnsupportedProtocolFailure(this.kind);

  final UnsupportedProtocolFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.unsupportedProtocol;
}

enum UnsupportedProtocolFailureKind { version, eventKind, capability }

final class CancellationFailure extends Failure {
  const CancellationFailure(this.kind);

  final CancellationFailureKind kind;

  @override
  FailureCategory get category => FailureCategory.cancellation;
}

enum CancellationFailureKind { requestedByUser, lifecycleInterrupted }
