import 'dart:typed_data';

import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/pairwise_crypto_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/pairwise_crypto_native_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adds fixed request framing and validates the matching response', () {
    final api = _Api(
      NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList([
          ...'CPPWO001'.codeUnits,
          PairwiseCryptoOperation.ratchetEncrypt.wireValue,
          0,
          7,
          8,
        ]),
      ),
    );
    final session = PairwiseCryptoNativeSession(api: api);

    final result = session.operation(
      PairwiseCryptoOperation.ratchetEncrypt,
      Uint8List.fromList([1, 2, 3]),
    );

    expect(api.operationId, PairwiseCryptoOperation.ratchetEncrypt.wireValue);
    expect(api.input, [...'CPPWR001'.codeUnits, 1, 2, 3]);
    expect(result, isA<Success<PairwiseCryptoResponse>>());
    final response = (result as Success<PairwiseCryptoResponse>).value;
    expect(response.outcome, PairwiseCryptoOutcome.ok);
    expect(response.body, [7, 8]);
  });

  test('preserves typed repair-required without treating it as mutation', () {
    final api = _Api(
      NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList([
          ...'CPPWO001'.codeUnits,
          PairwiseCryptoOperation.ratchetDecrypt.wireValue,
          1,
          1,
        ]),
      ),
    );

    final result = PairwiseCryptoNativeSession(
      api: api,
    ).operation(PairwiseCryptoOperation.ratchetDecrypt, Uint8List(0));

    final response = (result as Success<PairwiseCryptoResponse>).value;
    expect(response.outcome, PairwiseCryptoOutcome.repairRequired);
    expect(response.mutatesState, isFalse);
    expect(response.body, [1]);
  });

  test('wrong operation echo fails closed', () {
    final api = _Api(
      NativeBufferResult(
        statusCode: 0,
        bytes: Uint8List.fromList([
          ...'CPPWO001'.codeUnits,
          PairwiseCryptoOperation.ratchetDecrypt.wireValue,
          0,
        ]),
      ),
    );

    final result = PairwiseCryptoNativeSession(
      api: api,
    ).operation(PairwiseCryptoOperation.ratchetEncrypt, Uint8List(0));

    expect(result, isA<FailureResult<PairwiseCryptoResponse>>());
    expect(
      (result as FailureResult<PairwiseCryptoResponse>).failure,
      isA<SecurityFailure>(),
    );
  });

  test('native authentication failure remains a typed crypto failure', () {
    final result = PairwiseCryptoNativeSession(
      api: _Api(const NativeBufferResult(statusCode: 7)),
    ).operation(PairwiseCryptoOperation.initiate, Uint8List(0));

    expect(result, isA<FailureResult<PairwiseCryptoResponse>>());
    final failure = (result as FailureResult<PairwiseCryptoResponse>).failure;
    expect(failure, isA<CryptoCoreFailure>());
    expect(
      (failure as CryptoCoreFailure).code,
      CryptoCoreFailureCode.authenticationFailed,
    );
  });
}

final class _Api implements PairwiseCryptoNativeApi {
  _Api(this.result);

  final NativeBufferResult result;
  int? operationId;
  Uint8List? input;

  @override
  NativeBufferResult operation(int operation, Uint8List input) {
    operationId = operation;
    this.input = Uint8List.fromList(input);
    return result;
  }
}
