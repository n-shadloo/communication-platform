import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/presentation/state/view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every failure family has a stable presentation classification', () {
    final failures = <Failure>[
      const TransportFailure(TransportFailureKind.offline),
      const AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      const ValidationFailure(ValidationFailureKind.invalidInput),
      const SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      const StorageFailure(StorageFailureKind.migrationBlocked),
      const UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.version),
      const CancellationFailure(CancellationFailureKind.requestedByUser),
    ];

    expect(failures.map((failure) => failure.category), FailureCategory.values);
  });

  test('result and view state preserve a typed failure without text', () {
    const failure = SecurityFailure(SecurityFailureKind.unauthenticatedInput);
    const result = Result<void>.failure(failure);
    const state = ViewState<void>.failure(failure);

    expect(
      result.fold(
        onSuccess: (_) => 'success',
        onFailure: (failure) => failure.category.name,
      ),
      'security',
    );
    expect((state as FailureViewState<void>).failure, same(failure));
  });
}
