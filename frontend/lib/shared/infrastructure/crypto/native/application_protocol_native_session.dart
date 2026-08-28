import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/application_protocol_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_native_session.dart';

final class ApplicationProtocolNativeSession {
  const ApplicationProtocolNativeSession({required this.api});

  final ApplicationProtocolNativeApi api;

  Result<Uint8List> operation(int operation, Uint8List input) {
    if (operation < 1 || operation > 9 || input.length > 262144) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final native = api.operation(operation, input);
    if (native.statusCode != 0) {
      return Result.failure(
        cryptoCoreFailureFromNativeStatus(native.statusCode),
      );
    }
    final bytes = native.bytes;
    if (bytes == null || bytes.length < 8) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    return Result.success(Uint8List.fromList(bytes));
  }
}
