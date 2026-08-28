import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/attachment_crypto_port.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/attachment_crypto_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/crypto_core_native_session.dart';

final class AttachmentCryptoNativeSession implements AttachmentCryptoPort {
  const AttachmentCryptoNativeSession({required this.api});

  final AttachmentCryptoNativeApi api;

  @override
  Future<Result<AttachmentCryptoPushSession>> createPush({
    required int plaintextSize,
    required int bucketSize,
    required Uint8List metadata,
  }) async {
    if (plaintextSize < 0 ||
        !AttachmentCryptoProtocolV1.buckets.contains(bucketSize) ||
        metadata.length > AttachmentCryptoProtocolV1.maximumMetadataBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPARQ001'))
      ..add(_u64(plaintextSize))
      ..add(_u32(AttachmentCryptoProtocolV1.chunkBytes))
      ..add(_u64(bucketSize))
      ..add(_u32(metadata.length))
      ..add(metadata);
    final result = _operation(1, input.takeBytes());
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final bytes = (result as Success<Uint8List>).value;
      _expectMagic(bytes, 'CPARE001');
      if (bytes.length != 8 + 8 + 32 + 66 + 24 + 8) {
        throw const FormatException();
      }
      return Result.success(
        AttachmentCryptoPushSession(
          handle: _readU64(bytes, 8),
          key: bytes.sublist(16, 48),
          header: bytes.sublist(48, 114),
          secretstreamHeader: bytes.sublist(114, 138),
          plaintextSize: plaintextSize,
          streamSize: _readU64(bytes, 138),
          bucketSize: bucketSize,
        ),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  @override
  Future<Result<Uint8List>> pushChunk({
    required AttachmentCryptoPushSession session,
    required Uint8List plaintext,
    required bool finalChunk,
  }) async {
    if (plaintext.length > AttachmentCryptoProtocolV1.chunkBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.limitExceeded),
      );
    }
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPAPR001'))
      ..add(_u64(session.handle))
      ..add(<int>[finalChunk ? 1 : 0])
      ..add(plaintext);
    final result = _operation(2, input.takeBytes());
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final bytes = (result as Success<Uint8List>).value;
      _expectMagic(bytes, 'CPARO001');
      if (bytes.length < 9) throw const FormatException();
      return Result.success(Uint8List.fromList(bytes.sublist(9)));
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  @override
  Future<Result<AttachmentCryptoPullSession>> createPull({
    required Uint8List key,
    required Uint8List header,
    required Uint8List secretstreamHeader,
    required Uint8List metadata,
  }) async {
    if (key.length != 32 ||
        header.length != 66 ||
        secretstreamHeader.length != 24 ||
        metadata.length > AttachmentCryptoProtocolV1.maximumMetadataBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPAPD001'))
      ..add(key)
      ..add(header)
      ..add(secretstreamHeader)
      ..add(_u32(metadata.length))
      ..add(metadata);
    final result = _operation(3, input.takeBytes());
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final bytes = (result as Success<Uint8List>).value;
      _expectMagic(bytes, 'CPARE001');
      if (bytes.length != 16) throw const FormatException();
      return Result.success(AttachmentCryptoPullSession(_readU64(bytes, 8)));
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  @override
  Future<Result<AttachmentDecryptedChunk>> pullChunk({
    required AttachmentCryptoPullSession session,
    required Uint8List ciphertext,
  }) async {
    if (ciphertext.length < 17 ||
        ciphertext.length > AttachmentCryptoProtocolV1.chunkBytes + 17) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPAPC001'))
      ..add(_u64(session.handle))
      ..add(ciphertext);
    final result = _operation(4, input.takeBytes());
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final bytes = (result as Success<Uint8List>).value;
      _expectMagic(bytes, 'CPARO001');
      if (bytes.length < 9) throw const FormatException();
      return Result.success(
        AttachmentDecryptedChunk(
          finalChunk: bytes[8] == 1,
          plaintext: bytes.sublist(9),
        ),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  @override
  Future<Result<void>> closeSession({
    required int handle,
    bool abort = false,
  }) async {
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPAPX001'))
      ..add(_u64(handle))
      ..add(<int>[abort ? 1 : 0]);
    final result = _operation(5, input.takeBytes());
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      _expectMagic((result as Success<Uint8List>).value, 'CPARX001');
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  @override
  Future<Result<Uint8List>> randomBytes(int length) async {
    if (length < 0 || length > AttachmentCryptoProtocolV1.chunkBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.limitExceeded),
      );
    }
    final input = BytesBuilder(copy: false)
      ..add(_ascii('CPAPN001'))
      ..add(_u32(length));
    final output = _operation(6, input.takeBytes());
    if (output case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    try {
      final bytes = (output as Success<Uint8List>).value;
      _expectMagic(bytes, 'CPARN001');
      if (bytes.length != 8 + length) throw const FormatException();
      return Result.success(Uint8List.fromList(bytes.sublist(8)));
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }

  Result<Uint8List> _operation(int operation, Uint8List input) {
    final native = api.operation(operation, input);
    if (native.statusCode != 0) {
      return Result.failure(
        cryptoCoreFailureFromNativeStatus(native.statusCode),
      );
    }
    final bytes = native.bytes;
    if (bytes == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    return Result.success(Uint8List.fromList(bytes));
  }
}

Uint8List _ascii(String value) => Uint8List.fromList(value.codeUnits);

Uint8List _u32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

Uint8List _u64(int value) {
  final data = ByteData(8)..setUint64(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _readU64(Uint8List value, int offset) =>
    ByteData.sublistView(value).getUint64(offset, Endian.big);

void _expectMagic(Uint8List value, String magic) {
  if (value.length < 8 || String.fromCharCodes(value.sublist(0, 8)) != magic) {
    throw const FormatException();
  }
}
