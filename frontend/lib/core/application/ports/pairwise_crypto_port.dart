import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';

/// Reviewed Rust pairwise boundary.
///
/// [payload] is the operation-specific body. The adapter adds and verifies the
/// fixed request/response framing so application code cannot select another
/// protocol purpose or classical-only suite.
abstract interface class PairwiseCryptoPort implements Port {
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  });
}
