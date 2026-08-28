import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';

/// Streaming boundary for the shared Rust secretstream implementation.
///
/// Each call carries at most one 64 KiB chunk. The returned bytes are copied
/// out of the native buffer and callers must close/abort sessions in `finally`.
abstract interface class AttachmentCryptoPort implements Port {
  Future<Result<AttachmentCryptoPushSession>> createPush({
    required int plaintextSize,
    required int bucketSize,
    required Uint8List metadata,
  });

  Future<Result<Uint8List>> pushChunk({
    required AttachmentCryptoPushSession session,
    required Uint8List plaintext,
    required bool finalChunk,
  });

  Future<Result<AttachmentCryptoPullSession>> createPull({
    required Uint8List key,
    required Uint8List header,
    required Uint8List secretstreamHeader,
    required Uint8List metadata,
  });

  Future<Result<AttachmentDecryptedChunk>> pullChunk({
    required AttachmentCryptoPullSession session,
    required Uint8List ciphertext,
  });

  Future<Result<void>> closeSession({required int handle, bool abort});

  Future<Result<Uint8List>> randomBytes(int length);
}

final class AttachmentDecryptedChunk {
  AttachmentDecryptedChunk({
    required Uint8List plaintext,
    required this.finalChunk,
  }) : plaintext = Uint8List.fromList(plaintext);

  final Uint8List plaintext;
  final bool finalChunk;
}
