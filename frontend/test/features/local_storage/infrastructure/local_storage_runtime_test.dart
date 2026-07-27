import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logout closes memory, destroys key, then removes artifacts', () async {
    final calls = <String>[];
    final keyPort = _FakeKeyPort(calls: calls);
    final cleanup = _FakeCleanup(calls);
    final runtime = SecureLocalStorageRuntime(
      protectedStorage: keyPort,
      cleanup: cleanup,
      executorFactory: (_) => NativeDatabase.memory(),
    );
    expect(await runtime.open(), isA<Success<Object>>());

    await runtime.wipeForLogout();

    expect(calls, ['load', 'clear', 'destroy', 'erase']);
    expect(runtime.openedDatabase, isNull);
  });

  test('self and remote revocation expose explicit wipe commands', () async {
    for (final invoke in <Future<void> Function(SecureLocalStorageRuntime)>[
      (runtime) => runtime.wipeForSelfRevocation(),
      (runtime) => runtime.wipeForRemoteRevocation(),
    ]) {
      final calls = <String>[];
      final runtime = SecureLocalStorageRuntime(
        protectedStorage: _FakeKeyPort(calls: calls),
        cleanup: _FakeCleanup(calls),
        executorFactory: (_) => NativeDatabase.memory(),
      );
      await invoke(runtime);
      expect(calls, ['clear', 'destroy', 'erase']);
    }
  });

  for (final status in [
    PlatformStorageKeyStatus.wrappingKeyLost,
    PlatformStorageKeyStatus.integrityFailure,
  ]) {
    test('$status fails closed and triggers cryptographic wipe', () async {
      final calls = <String>[];
      final runtime = SecureLocalStorageRuntime(
        protectedStorage: _FakeKeyPort(calls: calls, status: status),
        cleanup: _FakeCleanup(calls),
        executorFactory: (_) => throw StateError('must not open'),
      );

      final result = await runtime.open();

      expect(result, isA<FailureResult<Object>>());
      expect(calls, ['load', 'clear', 'destroy', 'erase']);
    });
  }

  test('cleanup delegates with a caller-supplied hard bound', () async {
    final calls = <String>[];
    final runtime = SecureLocalStorageRuntime(
      protectedStorage: _FakeKeyPort(calls: calls),
      cleanup: _FakeCleanup(calls),
      executorFactory: (_) => NativeDatabase.memory(),
    );
    await runtime.open();

    final report = await runtime.cleanupBounded(maximumEntries: 8);

    expect(report.removedEntries, 2);
    expect(calls, ['load', 'cleanup:8']);
    await runtime.close();
  });
}

final class _FakeKeyPort implements PlatformProtectedStoragePort {
  _FakeKeyPort({
    required this.calls,
    this.status = PlatformStorageKeyStatus.ready,
  });

  final List<String> calls;
  final PlatformStorageKeyStatus status;

  @override
  Future<void> destroyWrappingKey() async {
    calls.add('destroy');
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async {
    calls.add('load');
    return PlatformStorageUnlock(
      status: status,
      protection: PlatformStorageProtection.unknown,
      databaseKey: status == PlatformStorageKeyStatus.ready
          ? Uint8List(32)
          : null,
    );
  }
}

final class _FakeCleanup implements LocalArtifactCleanupPort {
  _FakeCleanup(this.calls);

  final List<String> calls;

  @override
  Future<void> clearVolatilePlaintext() async {
    calls.add('clear');
  }

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async {
    calls.add('cleanup:$maximumEntries');
    return const CleanupReport(removedEntries: 2, hasMore: false);
  }

  @override
  Future<void> erasePersistentArtifacts() async {
    calls.add('erase');
  }
}
