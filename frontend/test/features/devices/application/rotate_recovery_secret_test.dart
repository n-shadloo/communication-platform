import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/rotate_recovery_secret.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recovery_rotation_fakes.dart';

/// Replacing a recovery secret has one property that matters above the others:
/// a user must never end up holding a written-down secret that opens nothing.
/// Every failure path below therefore asserts the *absence* of a secret, not
/// just the presence of an error.
void main() {
  late FakeIdentityStore identities;
  late FakeRotationCrypto crypto;
  late FakeEnrollmentRepository repository;
  late FakeBackupVersionStore versions;
  late RotateRecoverySecret rotate;

  setUp(() {
    identities = FakeIdentityStore();
    crypto = FakeRotationCrypto();
    repository = FakeEnrollmentRepository();
    versions = FakeBackupVersionStore();
    rotate = RotateRecoverySecret(
      identities: identities,
      crypto: crypto,
      repository: repository,
      versions: versions,
    );
  });

  test(
    'uploads above the recorded version and shows the new secret once',
    () async {
      versions.stored = 4;

      final result = await rotate.call();

      expect(result, isA<Success<RotatedRecoverySecret>>());
      final rotated = (result as Success<RotatedRecoverySecret>).value;
      expect(rotated.secret, rotatedRecoverySecret);
      expect(rotated.backupVersion, 5);
      expect(repository.uploads, [5]);
      expect(versions.stored, 5);
      // The identity that was re-wrapped is the one this device already holds:
      // a fresh one would silently un-verify every contact.
      expect(crypto.rotatedPackage, same(identities.completed));
      // Nothing local is rewritten. The private material did not change, so
      // there is no window where a crash leaves keys that do not match a backup.
      expect(identities.writes, isEmpty);
    },
  );

  test(
    'an unknown local version starts at one and lets the server correct it',
    () async {
      versions.readFailure = const StorageFailure(
        StorageFailureKind.unavailable,
      );
      repository.staleUntilVersion = 12;

      final result = await rotate.call();

      expect(repository.uploads, [1, 13]);
      expect(
        (result as Success<RotatedRecoverySecret>).value.backupVersion,
        13,
      );
      expect(versions.stored, 13);
    },
  );

  test('a stale version is retried once above what the server holds', () async {
    versions.stored = 2;
    repository.staleUntilVersion = 9;

    final result = await rotate.call();

    expect(repository.uploads, [3, 10]);
    expect((result as Success<RotatedRecoverySecret>).value.backupVersion, 10);
  });

  test('a refused upload shows no secret and records no version', () async {
    versions.stored = 4;
    repository.uploadFailure = const TransportFailure(
      TransportFailureKind.offline,
    );

    final result = await rotate.call();

    expect(result, isA<FailureResult<RotatedRecoverySecret>>());
    // The server still holds the blob the current secret opens, so the current
    // secret still works, and the device has not recorded a version it never
    // uploaded.
    expect(versions.stored, 4);
  });

  test(
    'a second refusal after a stale conflict still shows no secret',
    () async {
      versions.stored = 1;
      repository.staleUntilVersion = 3;
      repository.retryFailure = const TransportFailure(
        TransportFailureKind.timeout,
      );

      final result = await rotate.call();

      expect(result, isA<FailureResult<RotatedRecoverySecret>>());
      expect(versions.stored, 1);
    },
  );

  test(
    'a device with no completed identity is refused before anything runs',
    () async {
      identities.completed = null;

      final result = await rotate.call();

      expect(
        (result as FailureResult<RotatedRecoverySecret>).failure,
        isA<SecurityFailure>(),
      );
      expect(crypto.calls, 0);
      expect(repository.uploads, isEmpty);
    },
  );

  test('a rotation that produced no display material is refused', () async {
    crypto.returnsDisplayMaterial = false;

    final result = await rotate.call();

    expect(
      (result as FailureResult<RotatedRecoverySecret>).failure,
      isA<SecurityFailure>(),
    );
    expect(repository.uploads, isEmpty);
  });

  test('a failing crypto core never reaches the network', () async {
    crypto.failure = const CryptoCoreFailure(
      CryptoCoreFailureCode.entropyUnavailable,
    );

    final result = await rotate.call();

    expect(
      (result as FailureResult<RotatedRecoverySecret>).failure,
      isA<CryptoCoreFailure>(),
    );
    expect(repository.uploads, isEmpty);
    expect(versions.stored, 1);
  });

  test('the rotated secret is never in a diagnostic string', () {
    const rotated = RotatedRecoverySecret(
      secret: 'SECRET-VALUE',
      backupVersion: 3,
    );
    expect(rotated.toString(), isNot(contains('SECRET-VALUE')));
    expect(rotated.toString(), contains('redacted'));
  });
}
