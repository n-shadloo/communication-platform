import 'dart:async';
import 'dart:isolate';

import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/crypto_core_runtime.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_native_session.dart';

const int _handshakeReady = 0;
const int _handshakeFailed = 1;
const int _operationCapabilities = 1;
const int _operationSelfTest = 2;
const int _operationClose = 3;
const int _replySuccess = 0;
const int _replyFailure = 1;
const int _failureCryptoCore = 1;
const int _failureUnsupportedProtocol = 2;
const int _failureSecurity = 3;

/// Owns the native library and all native calls in one dedicated isolate.
final class IsolateCryptoCoreWorker implements CryptoCoreWorker {
  bool _closed = false;
  Future<_CryptoWorkerState?>? _stateFuture;
  Future<void>? _closeFuture;
  final Set<Future<void>> _inFlight = <Future<void>>{};

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() {
    return _guarded<CryptoCoreCapabilities>(() async {
      final reply = await _request(_operationCapabilities);
      return _decodeCapabilitiesReply(reply);
    });
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _closed = true;
    final closing = _closeAfterInFlight();
    _closeFuture = closing;
    return closing;
  }

  @override
  Future<Result<void>> selfTest() {
    return _guarded<void>(() async {
      final reply = await _request(_operationSelfTest);
      return _decodeSelfTestReply(reply);
    });
  }

  Future<Result<T>> _guarded<T>(Future<Result<T>> Function() operation) {
    if (_closed) {
      return Future<Result<T>>.value(
        Result<T>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    final completion = Completer<void>();
    final marker = completion.future;
    _inFlight.add(marker);
    return _runGuarded(operation, completion, marker);
  }

  Future<Result<T>> _runGuarded<T>(
    Future<Result<T>> Function() operation,
    Completer<void> completion,
    Future<void> marker,
  ) async {
    try {
      return await operation();
    } on Object {
      return Result<T>.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    } finally {
      _inFlight.remove(marker);
      completion.complete();
    }
  }

  Future<Object?> _request(int operation) async {
    final state = await _ensureState();
    if (state == null) {
      return null;
    }
    final replyPort = ReceivePort();
    try {
      state.commandPort.send(<Object?>[operation, replyPort.sendPort]);
      return await replyPort.first.timeout(
        const Duration(seconds: 60),
        onTimeout: () => null,
      );
    } finally {
      replyPort.close();
    }
  }

  Future<_CryptoWorkerState?> _ensureState() {
    if (_closed) {
      return Future<_CryptoWorkerState?>.value();
    }
    return _stateFuture ??= _startWorker();
  }

  Future<_CryptoWorkerState?> _startWorker() async {
    final bootstrapPort = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<SendPort>(
        _cryptoCoreWorkerEntrypoint,
        bootstrapPort.sendPort,
        debugName: 'communication-crypto-core-v1',
      );
      final handshake = await bootstrapPort.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const <Object?>[_handshakeFailed],
      );
      if (handshake is List<Object?> &&
          handshake.length == 2 &&
          handshake[0] == _handshakeReady &&
          handshake[1] is SendPort) {
        return _CryptoWorkerState(
          isolate: isolate,
          commandPort: handshake[1]! as SendPort,
        );
      }
      isolate.kill(priority: Isolate.immediate);
      return null;
    } on Object {
      isolate?.kill(priority: Isolate.immediate);
      return null;
    } finally {
      bootstrapPort.close();
    }
  }

  Future<void> _closeAfterInFlight() async {
    await Future.wait<void>(_inFlight.toList(growable: false));
    final stateFuture = _stateFuture;
    if (stateFuture == null) {
      return;
    }
    final state = await stateFuture;
    if (state == null) {
      return;
    }
    final replyPort = ReceivePort();
    try {
      state.commandPort.send(<Object?>[_operationClose, replyPort.sendPort]);
      await replyPort.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } on Object {
      // Shutdown remains best-effort; no exception details cross the boundary.
    } finally {
      replyPort.close();
      state.isolate.kill(priority: Isolate.immediate);
    }
  }

  @override
  String toString() => 'IsolateCryptoCoreWorker(<redacted>)';
}

final class _CryptoWorkerState {
  const _CryptoWorkerState({required this.isolate, required this.commandPort});

  final Isolate isolate;
  final SendPort commandPort;

  @override
  String toString() => '_CryptoWorkerState(<redacted>)';
}

@pragma('vm:entry-point')
void _cryptoCoreWorkerEntrypoint(SendPort bootstrapPort) {
  unawaited(_runCryptoCoreWorker(bootstrapPort));
}

Future<void> _runCryptoCoreWorker(SendPort bootstrapPort) async {
  final commandPort = ReceivePort();
  late final CryptoCoreNativeSession session;
  try {
    session = CryptoCoreNativeSession(
      api: DynamicCryptoCoreNativeApi.openAndroid(),
    );
  } on Object {
    bootstrapPort.send(const <Object?>[_handshakeFailed]);
    commandPort.close();
    return;
  }

  bootstrapPort.send(<Object?>[_handshakeReady, commandPort.sendPort]);
  try {
    await for (final Object? message in commandPort) {
      if (message is! List<Object?> || message.length != 2) {
        if (message is List<Object?> &&
            message.length >= 2 &&
            message[1] is SendPort) {
          (message[1]! as SendPort).send(
            _encodeFailureReply(
              const SecurityFailure(
                SecurityFailureKind.malformedServerResponse,
              ),
            ),
          );
        }
        continue;
      }
      final operation = message[0];
      final replyPort = message[1];
      if (operation is! int || replyPort is! SendPort) {
        continue;
      }
      try {
        switch (operation) {
          case _operationCapabilities:
            replyPort.send(_encodeCapabilitiesReply(session.capabilities()));
            continue;
          case _operationSelfTest:
            replyPort.send(_encodeSelfTestReply(session.selfTest()));
            continue;
          case _operationClose:
            replyPort.send(const <Object?>[_replySuccess]);
            commandPort.close();
            return;
          default:
            replyPort.send(
              _encodeFailureReply(
                const SecurityFailure(SecurityFailureKind.policyBlocked),
              ),
            );
            continue;
        }
      } on Object {
        replyPort.send(
          _encodeFailureReply(
            const SecurityFailure(SecurityFailureKind.policyBlocked),
          ),
        );
      }
    }
  } on Object {
    // All observable failures are converted to payload-free replies above.
  } finally {
    commandPort.close();
  }
}

List<Object?> _encodeCapabilitiesReply(Result<CryptoCoreCapabilities> result) {
  return result.fold(
    onSuccess: (capabilities) => <Object?>[
      _replySuccess,
      capabilities.abiVersion,
      capabilities.featureBits,
      capabilities.maxInputBytes,
      capabilities.maxCborDepth,
      capabilities.maxCborItems,
    ],
    onFailure: _encodeFailureReply,
  );
}

List<Object?> _encodeSelfTestReply(Result<void> result) {
  return result.fold(
    onSuccess: (_) => const <Object?>[_replySuccess],
    onFailure: _encodeFailureReply,
  );
}

List<Object?> _encodeFailureReply(Failure failure) {
  return switch (failure) {
    CryptoCoreFailure(:final code) => <Object?>[
      _replyFailure,
      _failureCryptoCore,
      code.wireValue,
    ],
    UnsupportedProtocolFailure(:final kind) => <Object?>[
      _replyFailure,
      _failureUnsupportedProtocol,
      kind.index,
    ],
    SecurityFailure(:final kind) => <Object?>[
      _replyFailure,
      _failureSecurity,
      kind.index,
    ],
    _ => <Object?>[
      _replyFailure,
      _failureSecurity,
      SecurityFailureKind.policyBlocked.index,
    ],
  };
}

Result<CryptoCoreCapabilities> _decodeCapabilitiesReply(Object? reply) {
  if (reply is! List<Object?> || reply.isEmpty) {
    return const Result<CryptoCoreCapabilities>.failure(
      SecurityFailure(SecurityFailureKind.policyBlocked),
    );
  }
  if (reply[0] == _replyFailure) {
    return Result<CryptoCoreCapabilities>.failure(_decodeFailureReply(reply));
  }
  if (reply.length != 6 ||
      reply[0] != _replySuccess ||
      reply[1] is! int ||
      reply[2] is! int ||
      reply[3] is! int ||
      reply[4] is! int ||
      reply[5] is! int) {
    return const Result<CryptoCoreCapabilities>.failure(
      SecurityFailure(SecurityFailureKind.malformedServerResponse),
    );
  }
  final capabilities = CryptoCoreCapabilities(
    abiVersion: reply[1]! as int,
    featureBits: reply[2]! as int,
    maxInputBytes: reply[3]! as int,
    maxCborDepth: reply[4]! as int,
    maxCborItems: reply[5]! as int,
  );
  if (capabilities.abiVersion != CryptoCoreProtocolV1.abiVersion ||
      capabilities.featureBits < 0 ||
      capabilities.maxInputBytes <= 0 ||
      capabilities.maxCborDepth <= 0 ||
      capabilities.maxCborItems <= 0 ||
      !capabilities.supportsRequiredFoundation) {
    return const Result<CryptoCoreCapabilities>.failure(
      SecurityFailure(SecurityFailureKind.policyBlocked),
    );
  }
  return Result<CryptoCoreCapabilities>.success(capabilities);
}

Result<void> _decodeSelfTestReply(Object? reply) {
  if (reply is! List<Object?> || reply.isEmpty) {
    return const Result<void>.failure(
      SecurityFailure(SecurityFailureKind.policyBlocked),
    );
  }
  if (reply[0] == _replyFailure) {
    return Result<void>.failure(_decodeFailureReply(reply));
  }
  if (reply.length != 1 || reply[0] != _replySuccess) {
    return const Result<void>.failure(
      SecurityFailure(SecurityFailureKind.malformedServerResponse),
    );
  }
  return const Result<void>.success(null);
}

Failure _decodeFailureReply(List<Object?> reply) {
  if (reply.length != 3 || reply[1] is! int || reply[2] is! int) {
    return const SecurityFailure(SecurityFailureKind.malformedServerResponse);
  }
  final failureKind = reply[1]! as int;
  final detail = reply[2]! as int;
  switch (failureKind) {
    case _failureCryptoCore:
      final code = CryptoCoreFailureCode.fromWireValue(detail);
      return code == null
          ? const SecurityFailure(SecurityFailureKind.policyBlocked)
          : CryptoCoreFailure(code);
    case _failureUnsupportedProtocol:
      if (detail >= 0 &&
          detail < UnsupportedProtocolFailureKind.values.length) {
        return UnsupportedProtocolFailure(
          UnsupportedProtocolFailureKind.values[detail],
        );
      }
      break;
    case _failureSecurity:
      if (detail >= 0 && detail < SecurityFailureKind.values.length) {
        return SecurityFailure(SecurityFailureKind.values[detail]);
      }
      break;
  }
  return const SecurityFailure(SecurityFailureKind.policyBlocked);
}
