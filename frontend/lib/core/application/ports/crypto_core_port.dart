import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/result.dart';

/// Narrow application boundary for the version-1 shared cryptographic core.
///
/// Piece 07 exposes capability discovery and a native self-test only. Later
/// protocol pieces may add opaque-handle operations after their wire contracts
/// are frozen; Dart must never implement cryptographic primitives.
abstract interface class CryptoCorePort implements Port {
  Future<Result<CryptoCoreCapabilities>> capabilities();

  Future<Result<void>> selfTest();

  Future<void> close();
}
