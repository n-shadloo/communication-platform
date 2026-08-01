import 'dart:io';

import 'package:communication_platform/core/application/cancellation_signal.dart';
import 'package:communication_platform/core/result/result.dart';

final class AttachmentUploadResponse {
  const AttachmentUploadResponse({
    required this.capabilityId,
    required this.bucketSize,
  });

  final String capabilityId;
  final int bucketSize;

  @override
  String toString() => 'AttachmentUploadResponse(<redacted>)';
}

abstract interface class AttachmentStoragePort {
  Future<File> createEncryptedTemp();

  Future<File> createDecryptedTemp({required String safeName});

  Future<void> delete(File file);
}

abstract interface class AttachmentTransportPort {
  Future<Result<AttachmentUploadResponse>> upload({
    required File encryptedFile,
    required int bucketSize,
    CancellationSignal? cancellation,
  });

  Future<Result<void>> download({
    required String capabilityId,
    required IOSink destination,
    required int expectedBucketSize,
    CancellationSignal? cancellation,
    void Function(int bytes)? onProgress,
  });
}
