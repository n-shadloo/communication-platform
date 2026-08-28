import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/devices/application/linked_device_manager.dart';
import 'package:communication_platform/features/devices/application/ports/linked_device_ports.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:communication_platform/features/devices/infrastructure/dio_device_enrollment_repository.dart';
import 'package:communication_platform/features/devices/infrastructure/dio_linked_device_repository.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_linked_device_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final linkedDeviceRemoteProvider = Provider<LinkedDeviceRemotePort>(
  (ref) =>
      DioLinkedDeviceRepository(ref.watch(authenticatedRestClientProvider)),
);

final linkedDeviceLocalProvider = FutureProvider<LinkedDeviceLocalPort>((
  ref,
) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return DriftLinkedDeviceRepository(database);
});

final selfRevocationCleanupProvider = Provider<SelfRevocationCleanupPort>(
  (ref) =>
      _RuntimeSelfRevocationCleanup(ref.watch(localStorageRuntimeProvider)),
);

final linkedDeviceManagerProvider = FutureProvider<LinkedDeviceManager>((
  ref,
) async {
  final local = await ref.watch(linkedDeviceLocalProvider.future);
  final identity = await local.readLocalIdentity();
  final tuple = identity.fold(
    onSuccess: (value) => value,
    onFailure: (failure) => throw LinkedDeviceAssemblyException(failure),
  );
  return LinkedDeviceManager(
    remote: ref.watch(linkedDeviceRemoteProvider),
    local: local,
    enrollment: DioDeviceEnrollmentRepository(
      ref.watch(authenticatedRestClientProvider),
    ),
    enrollmentCrypto: ref.watch(enrollmentCryptoProvider),
    identityCrypto: ref.watch(identityCryptoProvider),
    controlCrypto: ref.watch(deviceControlCryptoProvider),
    cleanup: ref.watch(selfRevocationCleanupProvider),
    userId: tuple.$1,
  );
});

final linkedDevicesProvider = StreamProvider<List<LinkedDevice>>((ref) async* {
  final local = await ref.watch(linkedDeviceLocalProvider.future);
  final identity = await local.readLocalIdentity();
  final userId = identity.fold(
    onSuccess: (value) => value.$1,
    onFailure: (_) => '',
  );
  await for (final rows in local.watchOwnDevices(userId)) {
    yield rows;
  }
});

final class _RuntimeSelfRevocationCleanup implements SelfRevocationCleanupPort {
  const _RuntimeSelfRevocationCleanup(this.runtime);
  final SecureLocalStorageRuntime runtime;
  @override
  Future<void> cleanupAfterSelfRevocation() => runtime.wipeForSelfRevocation();
}

final class LinkedDeviceAssemblyException implements Exception {
  const LinkedDeviceAssemblyException(this.cause);
  final Object cause;
}
