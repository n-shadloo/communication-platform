import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';

/// Testable worker boundary. Production implements this in one dedicated isolate.
abstract interface class CryptoCoreWorker {
  Future<Result<CryptoCoreCapabilities>> capabilities();

  Future<Result<void>> selfTest();

  Future<void> close();
}

/// Scope-owned lifecycle wrapper around the platform crypto worker.
final class CryptoCoreRuntime implements CryptoCorePort {
  CryptoCoreRuntime({required this.worker});

  final CryptoCoreWorker worker;
  bool _closed = false;

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() {
    if (_closed) {
      return Future<Result<CryptoCoreCapabilities>>.value(
        const Result<CryptoCoreCapabilities>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.capabilities();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await worker.close();
  }

  @override
  Future<Result<void>> selfTest() {
    if (_closed) {
      return Future<Result<void>>.value(
        const Result<void>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.selfTest();
  }

  @override
  String toString() => 'CryptoCoreRuntime(<redacted>)';
}

/// Fail-closed implementation used when the reviewed native boundary is absent.
final class UnsupportedCryptoCore implements CryptoCorePort {
  const UnsupportedCryptoCore();

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() async {
    return const Result<CryptoCoreCapabilities>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<Result<void>> selfTest() async {
    return const Result<void>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  String toString() => 'UnsupportedCryptoCore(<redacted>)';
}
