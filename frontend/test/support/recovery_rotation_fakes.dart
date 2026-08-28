import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/device_enrollment_ports.dart';
import 'package:communication_platform/features/devices/application/ports/recovery_rotation_ports.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';

/// The ports a recovery rotation needs, faked, so that both the use-case test
/// and the screen test drive the **real** [RotateRecoverySecret] rather than a
/// stand-in for it. A screen tested against a fake use case proves only that
/// the fake behaves; the property that matters here — no secret is shown unless
/// the server accepted the upload — belongs to the use case.
const currentRecoverySecret = 'AAAAA-BBBBB-CCCCC';
const rotatedRecoverySecret = 'DDDDD-EEEEE-FFFFF';

final class FakeIdentityStore implements EnrollmentJournalStore {
  FakeIdentityStore()
    : completed = identityPackage(secret: currentRecoverySecret);

  IdentityKeyPackage? completed;
  final writes = <Object>[];

  @override
  Future<Result<IdentityKeyPackage?>> readCompletedIdentity() async =>
      Result.success(completed);

  @override
  Future<Result<void>> update(EnrollmentJournal journal) async {
    writes.add(journal);
    return const Result.success(null);
  }

  @override
  Future<Result<void>> persistPrepared(EnrollmentJournal journal) async {
    writes.add(journal);
    return const Result.success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class FakeRotationCrypto implements EnrollmentCryptoPort {
  var calls = 0;
  var returnsDisplayMaterial = true;
  Failure? failure;
  IdentityKeyPackage? rotatedPackage;

  @override
  Future<Result<IdentityKeyPackage>> rotateRecoverySecret({
    required IdentityKeyPackage package,
  }) async {
    calls += 1;
    rotatedPackage = package;
    final error = failure;
    if (error != null) {
      return Result.failure(error);
    }
    return Result.success(
      returnsDisplayMaterial
          ? identityPackage(secret: rotatedRecoverySecret)
          : identityPackage(secret: null),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class FakeEnrollmentRepository implements DeviceEnrollmentRepository {
  final uploads = <int>[];
  int? staleUntilVersion;
  Failure? uploadFailure;
  Failure? retryFailure;

  @override
  Future<Result<void>> uploadBackup({
    required Uint8List blob,
    required int version,
  }) async {
    uploads.add(version);
    final refusal = uploads.length == 1 ? uploadFailure : retryFailure;
    if (refusal != null) {
      return Result.failure(refusal);
    }
    final stale = staleUntilVersion;
    if (stale != null && version <= stale) {
      return const Result.failure(
        BackendFailure(BackendFailureCode.staleVersion),
      );
    }
    return const Result.success(null);
  }

  @override
  Future<Result<KeyBackup>> fetchBackup() async => Result.success(
    KeyBackup(blob: Uint8List(4096), version: staleUntilVersion ?? 0),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class FakeBackupVersionStore implements RecoveryBackupVersionStore {
  var stored = 1;
  Failure? readFailure;

  @override
  Future<Result<int>> readBackupVersion() async {
    final failure = readFailure;
    return failure == null ? Result.success(stored) : Result.failure(failure);
  }

  @override
  Future<Result<void>> recordBackupVersion(int version) async {
    if (version > stored) {
      stored = version;
    }
    return const Result.success(null);
  }
}

/// A structurally valid identity package with the display fields a test
/// controls. The private key material is fixed test data, never a real secret.
IdentityKeyPackage identityPackage({required String? secret}) {
  final recovery = secret == null
      ? Uint8List(0)
      : Uint8List.fromList(utf8.encode(secret));
  final backup = secret == null ? Uint8List(0) : Uint8List(4096);
  final builder = BytesBuilder()
    ..add(const [67, 80, 73, 68, 86, 48, 48, 49])
    ..addByte((recovery.isEmpty ? 0 : 1) | (backup.isEmpty ? 0 : 2))
    ..add(List<int>.filled(16, 7))
    ..add(List<int>.filled(32, 1))
    ..add(List<int>.filled(32, 2))
    ..add(List<int>.filled(32, 3))
    ..add(List<int>.filled(64, 4));
  final lengths = ByteData(6)
    ..setUint16(0, recovery.length)
    ..setUint32(2, backup.length);
  builder
    ..add(lengths.buffer.asUint8List())
    ..add(List<int>.filled(96, 5))
    ..add(recovery)
    ..add(backup);
  return IdentityKeyPackage.fromNative(builder.toBytes());
}
