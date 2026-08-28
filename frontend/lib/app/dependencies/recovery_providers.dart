import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/devices/application/rotate_recovery_secret.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_recovery_backup_version_store.dart';
import 'package:communication_platform/features/devices/presentation/device_enrollment_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Replacing the recovery secret, built from the parts enrollment already owns.
///
/// It deliberately reuses `DeviceEnrollmentCoordinator`'s repository, journal
/// store and crypto port rather than composing a second set: a rotation that
/// went through a different enrollment repository could authenticate against a
/// different transport, and a rotation that read a different journal could
/// re-wrap an identity this device is not the one holding.
///
/// A build with no authenticated composition throws here, which the screen
/// catches and reports as a rotation that did not happen — the correct outcome,
/// because nothing was uploaded and the current secret still works.
final rotateRecoverySecretProvider = FutureProvider<RotateRecoverySecret>((
  ref,
) async {
  final coordinator = ref.watch(deviceEnrollmentCoordinatorProvider);
  final database = await ref.watch(localDatabaseProvider.future);
  return RotateRecoverySecret(
    identities: coordinator.store,
    crypto: ref.watch(enrollmentCryptoProvider),
    repository: coordinator.repository,
    versions: DriftRecoveryBackupVersionStore(database),
  );
});
