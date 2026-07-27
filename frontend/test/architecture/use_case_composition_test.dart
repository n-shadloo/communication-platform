import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/application/use_case.dart';
import 'package:communication_platform/core/domain/entity.dart';
import 'package:communication_platform/core/domain/value_object.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-only dependency-direction proof. It must not be promoted to a product module.
final _probeRepositoryProvider = Provider<_ProbeRepository>(
  (ref) => throw StateError('A test must provide an in-memory repository.'),
);

final _readProbeProvider = Provider<_ReadProbe>(
  (ref) => _ReadProbe(ref.watch(_probeRepositoryProvider)),
);

void main() {
  test(
    'a Riverpod-composed use case depends only on an application port',
    () async {
      final repository = _InMemoryProbeRepository(
        const _Probe(_ProbeId('architecture'), 'in-memory'),
      );
      final container = ProviderContainer(
        overrides: [_probeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(_readProbeProvider)
          .execute(const _ProbeId('architecture'));

      expect(
        result.fold(
          onSuccess: (probe) => probe.label,
          onFailure: (_) => 'failure',
        ),
        'in-memory',
      );
    },
  );
}

final class _ProbeId extends ValueObject {
  const _ProbeId(this.value);

  final String value;

  @override
  List<Object?> get equalityComponents => [value];
}

final class _Probe implements Entity<_ProbeId> {
  const _Probe(this.id, this.label);

  @override
  final _ProbeId id;
  final String label;
}

abstract interface class _ProbeRepository implements RepositoryPort {
  Future<Result<_Probe>> read(_ProbeId id);
}

final class _ReadProbe implements UseCase<_Probe, _ProbeId> {
  const _ReadProbe(this._repository);

  final _ProbeRepository _repository;

  @override
  Future<Result<_Probe>> execute(_ProbeId input) => _repository.read(input);
}

final class _InMemoryProbeRepository implements _ProbeRepository {
  _InMemoryProbeRepository(_Probe probe) : _probes = {probe.id: probe};

  final Map<_ProbeId, _Probe> _probes;

  @override
  Future<Result<_Probe>> read(_ProbeId id) async {
    final probe = _probes[id];
    return probe == null
        ? const Result.failure(
            ValidationFailure(ValidationFailureKind.invalidInput),
          )
        : Result.success(probe);
  }
}
