import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/device_enrollment_ports.dart';
import 'package:communication_platform/features/devices/application/ports/recovery_rotation_ports.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';

/// A replacement recovery secret, for exactly one showing.
///
/// It exists only between the moment the server accepted the new backup and the
/// moment the screen that displayed it is closed. Nothing writes it anywhere:
/// the application does not retain a recovery secret, which is the whole reason
/// replacement is the only remedy for a lost one.
final class RotatedRecoverySecret {
  const RotatedRecoverySecret({
    required this.secret,
    required this.backupVersion,
  });

  final String secret;
  final int backupVersion;

  @override
  String toString() => 'RotatedRecoverySecret(<redacted>)';
}

/// Replaces the recovery secret protecting this account's cross-signing
/// identity, without changing the identity.
///
/// The order matters and is the security property. The new secret is produced
/// locally, the re-wrapped backup is uploaded at a strictly higher version, and
/// only a server that accepted the upload causes the new secret to be shown.
/// If the upload fails at any point the caller is told the **old secret is
/// still the one that works** — the server still holds the blob it opens — so a
/// user can never be left having written down a secret that recovers nothing.
///
/// Nothing local is rewritten. The private cross-signing material on this
/// device is unchanged by construction, so there is no window in which a crash
/// leaves the device holding keys that do not match the backup: the only
/// durable local effect is the recorded backup version, and a stale one costs a
/// single extra round trip on the next rotation rather than a lost identity.
final class RotateRecoverySecret {
  const RotateRecoverySecret({
    required this.identities,
    required this.crypto,
    required this.repository,
    required this.versions,
  });

  final EnrollmentJournalStore identities;
  final EnrollmentCryptoPort crypto;
  final DeviceEnrollmentRepository repository;
  final RecoveryBackupVersionStore versions;

  Future<Result<RotatedRecoverySecret>> call() async {
    final stored = await identities.readCompletedIdentity();
    if (stored case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final identity = (stored as Success<IdentityKeyPackage?>).value;
    if (identity == null) {
      // No completed identity on this device: enrollment has not finished, or
      // this device holds none. There is nothing to re-wrap, and generating a
      // fresh identity here would silently un-verify every contact.
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }

    final rotated = await crypto.rotateRecoverySecret(package: identity);
    if (rotated case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final package = (rotated as Success<IdentityKeyPackage>).value;
    final secret = package.recoverySecret;
    if (secret == null || package.backup.isEmpty) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }

    final known = await versions.readBackupVersion();
    var attempt = switch (known) {
      Success(value: final version) => version + 1,
      FailureResult() => 1,
    };

    var upload = await repository.uploadBackup(
      blob: package.backup,
      version: attempt,
    );
    if (upload case FailureResult(failure: final failure)) {
      if (failure is! BackendFailure ||
          failure.code != BackendFailureCode.staleVersion) {
        return Result.failure(failure);
      }
      // The server holds a higher version than this device knew about — a
      // rotation from another device, or a first upload this one never
      // recorded. Its answer is authoritative; retry once above it rather than
      // climbing.
      final existing = await repository.fetchBackup();
      if (existing case FailureResult(failure: final fetchFailure)) {
        return Result.failure(fetchFailure);
      }
      attempt = (existing as Success<KeyBackup>).value.version + 1;
      upload = await repository.uploadBackup(
        blob: package.backup,
        version: attempt,
      );
      if (upload case FailureResult(failure: final retryFailure)) {
        return Result.failure(retryFailure);
      }
    }

    // Recorded after the server accepted, never before: a version written first
    // and uploaded second would leave a device believing it had raised a
    // version the server never took.
    await versions.recordBackupVersion(attempt);
    return Result.success(
      RotatedRecoverySecret(secret: secret, backupVersion: attempt),
    );
  }
}
