import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/device_enrollment_ports.dart';
import 'package:communication_platform/features/devices/application/ports/prekey_maintenance_ports.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';
import 'package:communication_platform/features/devices/domain/prekey_maintenance_model.dart';

/// Authenticated device-log adapter used after an atomic signed-prekey upload.
///
/// The server response is never trusted as proof that the rotation was
/// published.  The current identity, complete log chain, current live set, and
/// exact rotated bundle are all re-read before an append.  An ambiguous append
/// is reconciled by looking for the exact durable record.
final class VerifiedRotationDeviceLog implements RotationDeviceLogPort {
  const VerifiedRotationDeviceLog({
    required this.userId,
    required this.repository,
    required this.journal,
    required this.crypto,
    required this.clock,
  });

  final String userId;
  final DeviceEnrollmentRepository repository;
  final EnrollmentJournalStore journal;
  final EnrollmentCryptoPort crypto;
  final TimeSource clock;

  @override
  Future<Result<PreparedRotationDeviceLog>> prepareOwnRotation(
    PrekeyMaintenancePlan plan,
  ) async {
    final rotation = plan.upload.rotation;
    if (!_isUuid(userId) ||
        rotation == null ||
        plan.stage !=
            PrekeyMaintenanceStage.uploadAcceptedAwaitingDeviceLogPreparation) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final identityResult = await journal.readCompletedIdentity();
    if (identityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final identity = (identityResult as Success<IdentityKeyPackage?>).value;
    if (identity == null || !_same(identity.userId, _uuidBytes(userId))) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final publishedResult = await repository.fetchIdentity(userId: userId);
    if (publishedResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final published = (publishedResult as Success<PublishedIdentity>).value;
    if (published.version <= 0 || !_identityMatches(identity, published)) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final verifiedResult = await _verifiedLog(identity);
    if (verifiedResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final verified = (verifiedResult as Success<_VerifiedLog>).value;
    final devicesResult = await repository.fetchPublicDevices(userId: userId);
    if (devicesResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final devices = (devicesResult as Success<PublicDeviceList>).value;
    if (devices.logHeadSequence != verified.nullableHeadSequence) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    }
    final own = devices.devices
        .where((device) => device.deviceId == plan.deviceId)
        .toList(growable: false);
    if (own.length != 1 ||
        own.single.isUnsigned ||
        own.single.bundleVersion != rotation.bundleVersion ||
        own.single.crossSignature == null ||
        !_same(own.single.crossSignature!, rotation.crossSignature) ||
        own.single.ikPub.length != 64) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final canonical = _canonicalLiveSet(devices.devices);
    if (canonical == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    final userBytes = _uuidBytes(userId);
    final recordResult = await crypto.createDeviceLogRecord(
      identity: identity,
      userId: userBytes,
      sequence: verified.headSequence + 1,
      previousHash: verified.headHash,
      canonicalLiveSet: canonical,
      identityVersion: published.version,
      coarseUnixDay: _unixDay(),
    );
    userBytes.fillRange(0, userBytes.length, 0);
    if (recordResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return Result.success(
      PreparedRotationDeviceLog(
        expectedSequence: verified.headSequence + 1,
        previousHeadHash: verified.headHash,
        exactRecord: (recordResult as Success<Uint8List>).value,
      ),
    );
  }

  @override
  Future<Result<void>> appendOrReconcile(
    PreparedRotationDeviceLog prepared,
  ) async {
    if (prepared.expectedSequence < 0 ||
        prepared.previousHeadHash.length != 32 ||
        prepared.exactRecord.length != enrollmentDeviceLogBucketBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final identityResult = await journal.readCompletedIdentity();
    if (identityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final identity = (identityResult as Success<IdentityKeyPackage?>).value;
    if (identity == null || !_same(identity.userId, _uuidBytes(userId))) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final beforeResult = await _verifiedLog(identity);
    if (beforeResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final before = (beforeResult as Success<_VerifiedLog>).value;
    final existing = before.records
        .where((entry) => entry.sequence == prepared.expectedSequence)
        .firstOrNull;
    if (existing != null) {
      return _same(existing.blob, prepared.exactRecord)
          ? const Result.success(null)
          : const Result.failure(
              ValidationFailure(ValidationFailureKind.conflict),
            );
    }
    if (before.headSequence != prepared.expectedSequence - 1 ||
        (prepared.expectedSequence == 0
            ? prepared.previousHeadHash.isNotEmpty
            : !_same(prepared.previousHeadHash, before.headHash))) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    }
    final appended = await repository.appendDeviceLog(
      record: prepared.exactRecord,
    );
    if (appended case Success<DeviceLogAppendResult>(:final value)) {
      if (value.firstSequence == prepared.expectedSequence &&
          value.lastSequence == prepared.expectedSequence) {
        return const Result.success(null);
      }
    }
    // The append endpoint is deliberately non-replay-safe.  Re-read the
    // authenticated chain before exposing an ambiguous failure to the caller.
    final afterResult = await _verifiedLog(identity);
    if (afterResult case Success<_VerifiedLog>(:final value)) {
      final committed = value.records
          .where((entry) => entry.sequence == prepared.expectedSequence)
          .firstOrNull;
      if (committed != null && _same(committed.blob, prepared.exactRecord)) {
        return const Result.success(null);
      }
    }
    if (appended case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return const Result.failure(
      ValidationFailure(ValidationFailureKind.conflict),
    );
  }

  Future<Result<_VerifiedLog>> _verifiedLog(IdentityKeyPackage identity) async {
    final userBytes = _uuidBytes(userId);
    final records = <DeviceLogRecord>[];
    int? fixedHead;
    int? after;
    var expectedSequence = 0;
    var previousHash = Uint8List(32);
    try {
      for (var pageIndex = 0; pageIndex < 50; pageIndex += 1) {
        final pageResult = await repository.fetchDeviceLog(
          userId: userId,
          after: after,
        );
        if (pageResult case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
        final page = (pageResult as Success<DeviceLogPage>).value;
        fixedHead ??= page.headSequence;
        if (fixedHead != page.headSequence ||
            (page.hasMore && page.records.isEmpty)) {
          return const Result.failure(
            ValidationFailure(ValidationFailureKind.conflict),
          );
        }
        for (final record in page.records) {
          if (record.sequence != expectedSequence || records.length >= 10000) {
            return const Result.failure(
              SecurityFailure(SecurityFailureKind.unauthenticatedInput),
            );
          }
          final inspected = await crypto.inspectDeviceLogRecord(
            identity: identity,
            userId: userBytes,
            record: record.blob,
          );
          if (inspected case FailureResult(failure: final failure)) {
            return Result.failure(failure);
          }
          final value = (inspected as Success<DeviceLogInspection>).value;
          if (value.sequence != record.sequence ||
              !_same(value.previousHash, previousHash)) {
            return const Result.failure(
              SecurityFailure(SecurityFailureKind.unauthenticatedInput),
            );
          }
          previousHash = value.recordHash;
          records.add(record);
          expectedSequence += 1;
          after = record.sequence;
        }
        if (!page.hasMore) {
          final expectedHead = records.isEmpty ? null : records.last.sequence;
          if (page.headSequence != expectedHead) {
            return const Result.failure(
              ValidationFailure(ValidationFailureKind.conflict),
            );
          }
          return Result.success(
            _VerifiedLog(
              records: records,
              headSequence: expectedHead ?? -1,
              headHash: records.isEmpty ? Uint8List(0) : previousHash,
            ),
          );
        }
      }
      return const Result.failure(
        CryptoCoreFailure(CryptoCoreFailureCode.resourceExhausted),
      );
    } finally {
      userBytes.fillRange(0, userBytes.length, 0);
    }
  }

  Uint8List? _canonicalLiveSet(List<PublicDevice> devices) {
    final sorted = [...devices]
      ..sort((left, right) => left.deviceId.compareTo(right.deviceId));
    final builder = BytesBuilder(copy: false)
      ..add(utf8.encode('chat:v1:device-set'))
      ..add(_u32(sorted.length));
    String? previousId;
    for (final device in sorted) {
      if (device.deviceId == previousId) {
        return null;
      }
      previousId = device.deviceId;
      final id = _uuidBytesOrNull(device.deviceId);
      if (id == null ||
          device.ikPub.length != 64 ||
          (device.crossSignature != null &&
              device.crossSignature!.length != 64)) {
        return null;
      }
      builder
        ..add(id)
        ..add(_frame(device.ikPub))
        ..add(_u32(device.registrationId))
        ..add(_frame(device.crossSignature ?? Uint8List(0)))
        ..add(_u32(device.bundleVersion ?? 0));
    }
    return builder.takeBytes();
  }

  bool _identityMatches(IdentityKeyPackage local, PublishedIdentity server) =>
      _same(local.masterPub, server.masterPub) &&
      _same(local.selfSigningPub, server.selfSigningPub) &&
      _same(local.userSigningPub, server.userSigningPub) &&
      _same(local.masterSig, server.masterSig);

  Uint8List _frame(Uint8List value) =>
      Uint8List.fromList([..._u32(value.length), ...value]);

  Uint8List _u32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);

  Uint8List _uuidBytes(String value) => _uuidBytesOrNull(value)!;

  Uint8List? _uuidBytesOrNull(String value) {
    final compact = value.replaceAll('-', '');
    if (compact.length != 32 ||
        !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
      return null;
    }
    final result = Uint8List(16);
    for (var index = 0; index < 16; index += 1) {
      result[index] = int.parse(
        compact.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return result;
  }

  bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  int _unixDay() =>
      clock.now().toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  bool _isUuid(String value) => _uuid.hasMatch(value);
}

final class _VerifiedLog {
  const _VerifiedLog({
    required this.records,
    required this.headSequence,
    required this.headHash,
  });

  final List<DeviceLogRecord> records;
  final int headSequence;
  final Uint8List headHash;

  int? get nullableHeadSequence => headSequence < 0 ? null : headSequence;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
