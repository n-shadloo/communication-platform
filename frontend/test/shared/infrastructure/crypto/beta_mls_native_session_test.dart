import 'dart:typed_data';

import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/beta_mls_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/beta_mls_native_session.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frames authenticated inputs and decodes exact consumable buckets', () {
    final responseBytes = _response(
      operation: 1,
      opaqueState: Uint8List.fromList([9, 8, 7]),
      packages: [Uint8List(4096)..fillRange(0, 4096, 0x41)],
    );
    final api = _Api(NativeBufferResult(statusCode: 0, bytes: responseBytes));
    final request = _request();

    final result = BetaMlsNativeSession(api: api).generate(request);

    expect(api.operationId, 1);
    expect(api.input!.sublist(0, 8), 'CPMLR001'.codeUnits);
    expect(result, isA<Success<GeneratedMlsKeyPackages>>());
    final generated = (result as Success<GeneratedMlsKeyPackages>).value;
    expect(generated.kind, MlsKeyPackageKind.consumable);
    expect(generated.opaqueKeyPackageState, [9, 8, 7]);
    expect(generated.wrappedKeyPackages.single, hasLength(4096));
    expect(responseBytes.every((byte) => byte == 0), isTrue);
  });

  test('rejects a mismatched count and off-bucket KeyPackage', () {
    final malformed = _response(
      operation: 1,
      opaqueState: Uint8List.fromList([1]),
      packages: [Uint8List(4095)],
    );

    final result = BetaMlsNativeSession(
      api: _Api(NativeBufferResult(statusCode: 0, bytes: malformed)),
    ).generate(_request());

    expect(result, isA<FailureResult<GeneratedMlsKeyPackages>>());
    expect(
      (result as FailureResult<GeneratedMlsKeyPackages>).failure,
      const SecurityFailure(SecurityFailureKind.malformedServerResponse),
    );
  });

  test('keeps native authentication failures typed and payload-free', () {
    final result = BetaMlsNativeSession(
      api: _Api(const NativeBufferResult(statusCode: 7)),
    ).generate(_request());

    expect(result, isA<FailureResult<GeneratedMlsKeyPackages>>());
    final failure = (result as FailureResult<GeneratedMlsKeyPackages>).failure;
    expect(failure, isA<CryptoCoreFailure>());
    expect(
      (failure as CryptoCoreFailure).code,
      CryptoCoreFailureCode.authenticationFailed,
    );
  });

  test('last-resort lifecycle permits exactly one package', () {
    expect(
      () => MlsKeyPackageGenerationRequest(
        opaqueDeviceState: Uint8List.fromList([1]),
        migrationUnixDay: 1,
        localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
        count: 2,
        kind: MlsKeyPackageKind.lastResort,
      ),
      throwsA(isA<MlsKeyPackageFormatException>()),
    );
  });

  test('creates a group and decodes the complete commit transaction', () {
    final responseBytes = _commitResponse(operation: 3, epoch: 1);
    final api = _Api(NativeBufferResult(statusCode: 0, bytes: responseBytes));

    final result = BetaMlsNativeSession(api: api).createGroup(
      BetaMlsCreateRequest(
        authentication: _authentication(),
        wrappedKeyPackages: [Uint8List(4096)..fillRange(0, 4096, 0x31)],
        authenticatedData: Uint8List.fromList([7, 8]),
      ),
    );

    expect(api.operationId, 3);
    expect(api.input!.sublist(0, 8), 'CPMLR001'.codeUnits);
    expect(result, isA<Success<BetaMlsCommitOutput>>());
    final output = (result as Success<BetaMlsCommitOutput>).value;
    expect(output.sealedGroupState, [1, 2, 3]);
    expect(output.commit, [4, 5]);
    expect(output.commitDigest, List<int>.filled(32, 5));
    expect(output.authenticationBundleRequests.single, 'CPBRV001'.codeUnits);
    expect(output.welcomes.single, [6]);
    expect(output.groupInfo, [7]);
    expect(output.groupId, List<int>.filled(32, 8));
    expect(output.epoch, 1);
    expect(output.exporterConfirmation, List<int>.filled(32, 9));
    expect(responseBytes.every((byte) => byte == 0), isTrue);
  });

  test('joins with updated sealed KeyPackage and group states', () {
    final responseBytes = _joinResponse(epoch: 0x100000002);
    final result =
        BetaMlsNativeSession(
          api: _Api(NativeBufferResult(statusCode: 0, bytes: responseBytes)),
        ).joinGroup(
          BetaMlsJoinRequest(
            authentication: _authentication(),
            sealedKeyPackageState: Uint8List.fromList([1]),
            welcome: Uint8List.fromList([2]),
          ),
        );

    expect(result, isA<Success<BetaMlsJoinOutput>>());
    final output = (result as Success<BetaMlsJoinOutput>).value;
    expect(output.sealedGroupState, [10]);
    expect(output.sealedKeyPackageState, [11]);
    expect(output.epoch, 0x100000002);
    expect(output.roster, hasLength(2));
    expect(output.roster.first.userId, List<int>.filled(16, 14));
    expect(output.roster.first.deviceId, List<int>.filled(16, 15));
  });

  test('processes control messages with intentionally empty data fields', () {
    final responseBytes = _processedResponse();
    final result =
        BetaMlsNativeSession(
          api: _Api(NativeBufferResult(statusCode: 0, bytes: responseBytes)),
        ).processMessage(
          BetaMlsProcessMessageRequest(
            authentication: _authentication(),
            sealedGroupState: Uint8List.fromList([1]),
            message: Uint8List.fromList([2]),
          ),
        );

    expect(result, isA<Success<BetaMlsProcessedMessage>>());
    final output = (result as Success<BetaMlsProcessedMessage>).value;
    expect(output.kind, BetaMlsReceivedKind.commit);
    expect(output.messageDigest, List<int>.filled(32, 16));
    expect(output.senderUserId, List<int>.filled(16, 17));
    expect(output.senderDeviceId, List<int>.filled(16, 18));
    expect(output.senderLeafIndex, 3);
    expect(output.data, isEmpty);
    expect(output.authenticatedData, isEmpty);
    expect(output.epoch, 4);
  });

  test('rejects a lifecycle response with trailing bytes', () {
    final malformed = BytesBuilder(copy: false)
      ..add(_commitResponse(operation: 5, epoch: 2))
      ..addByte(0xff);
    final result =
        BetaMlsNativeSession(
          api: _Api(
            NativeBufferResult(statusCode: 0, bytes: malformed.takeBytes()),
          ),
        ).addMembers(
          BetaMlsAddMembersRequest(
            authentication: _authentication(),
            sealedGroupState: Uint8List.fromList([1]),
            wrappedKeyPackages: [Uint8List(4096)],
            authenticatedData: Uint8List(0),
          ),
        );

    expect(result, isA<FailureResult<BetaMlsCommitOutput>>());
    expect(
      (result as FailureResult<BetaMlsCommitOutput>).failure,
      const SecurityFailure(SecurityFailureKind.malformedServerResponse),
    );
  });

  test(
    'signs typed control fields and decodes only native canonical output',
    () {
      final responseBytes = _signedControlResponse();
      final api = _Api(NativeBufferResult(statusCode: 0, bytes: responseBytes));
      final result = BetaMlsNativeSession(api: api).signControl(
        BetaMlsSignControlRequest(
          authentication: _authentication(),
          descriptor: _controlDescriptor(),
        ),
      );

      expect(api.operationId, 11);
      expect(result, isA<Success<BetaMlsSignedControlOutput>>());
      final output = (result as Success<BetaMlsSignedControlOutput>).value;
      expect(output.canonicalBytes, [1, 2, 3]);
      expect(output.signature, List<int>.filled(64, 4));
      expect(output.controlStateHash, List<int>.filled(32, 5));
      expect(output.signedPayload, [6, 7]);
      expect(output.signerUserId, List<int>.filled(16, 8));
      expect(output.signerDeviceId, List<int>.filled(16, 9));
      expect(responseBytes.every((byte) => byte == 0), isTrue);
    },
  );
}

BetaMlsControlDescriptor _controlDescriptor() => BetaMlsControlDescriptor(
  eventId: Uint8List.fromList(List<int>.filled(16, 1)),
  groupId: Uint8List.fromList(List<int>.filled(32, 2)),
  revision: 1,
  mlsEpoch: 1,
  mlsCommitHash: Uint8List.fromList(List<int>.filled(32, 3)),
  createdMs: 1_700_000_000_000,
  operation: BetaMlsCreateControlInput(
    metadata: BetaMlsControlMetadata(name: 'Beta group'),
    invitationPolicy: 1,
    historyPolicy: 0,
    members: [
      BetaMlsControlMember(
        userId: Uint8List.fromList(List<int>.filled(16, 8)),
        displayName: 'Alice',
        role: 0,
        membership: 0,
        verified: true,
        deviceIds: [Uint8List.fromList(List<int>.filled(16, 9))],
      ),
    ],
  ),
);

BetaMlsAuthenticationInput _authentication() => BetaMlsAuthenticationInput(
  opaqueDeviceState: Uint8List.fromList([1, 2, 3]),
  migrationUnixDay: 20_302,
  localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
);

MlsKeyPackageGenerationRequest _request() => MlsKeyPackageGenerationRequest(
  opaqueDeviceState: Uint8List.fromList([1, 2, 3]),
  migrationUnixDay: 20_302,
  localVerifiedBundleRequest: Uint8List.fromList('CPBRV001'.codeUnits),
  count: 1,
  kind: MlsKeyPackageKind.consumable,
);

Uint8List _response({
  required int operation,
  required Uint8List opaqueState,
  required List<Uint8List> packages,
}) {
  final builder = BytesBuilder(copy: false)
    ..add('CPMLO001'.codeUnits)
    ..add([0, 1, operation])
    ..add(_frame(opaqueState))
    ..add([(packages.length >>> 8) & 0xff, packages.length & 0xff]);
  for (final package in packages) {
    builder.add(_frame(package));
  }
  return builder.takeBytes();
}

Uint8List _commitResponse({required int operation, required int epoch}) {
  final builder = BytesBuilder(copy: false)
    ..add(_header(operation))
    ..add(_frame(Uint8List.fromList([1, 2, 3])))
    ..add(_frame(Uint8List.fromList([4, 5])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 5))))
    ..add([0, 1])
    ..add(_frame(Uint8List.fromList('CPBRV001'.codeUnits)))
    ..add([0, 1])
    ..add(_frame(Uint8List.fromList([6])))
    ..add(_frame(Uint8List.fromList([7])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 8))))
    ..add(_u64(epoch))
    ..add(List<int>.filled(32, 9));
  return builder.takeBytes();
}

Uint8List _joinResponse({required int epoch}) {
  final builder = BytesBuilder(copy: false)
    ..add(_header(4))
    ..add(_frame(Uint8List.fromList([10])))
    ..add(_frame(Uint8List.fromList([11])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 12))))
    ..add(_u64(epoch))
    ..add([0, 2])
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 14))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 15))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 16))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 17))))
    ..add(List<int>.filled(32, 13));
  return builder.takeBytes();
}

Uint8List _processedResponse() {
  final builder = BytesBuilder(copy: false)
    ..add(_header(8))
    ..add(_frame(Uint8List.fromList([1, 2])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 16))))
    ..addByte(2)
    ..add([0, 0, 0, 3])
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 17))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 18))))
    ..add(_frame(Uint8List(0)))
    ..add(_frame(Uint8List(0)))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 14))))
    ..add(_u64(4))
    ..add(List<int>.filled(32, 15));
  return builder.takeBytes();
}

Uint8List _signedControlResponse() {
  final builder = BytesBuilder(copy: false)
    ..add(_header(11))
    ..add(_frame(Uint8List.fromList([1, 2, 3])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(64, 4))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(32, 5))))
    ..add(_frame(Uint8List.fromList([6, 7])))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 8))))
    ..add(_frame(Uint8List.fromList(List<int>.filled(16, 9))));
  return builder.takeBytes();
}

List<int> _header(int operation) => [...'CPMLO001'.codeUnits, 0, 1, operation];

List<int> _u64(int value) => [
  (value >>> 56) & 0xff,
  (value >>> 48) & 0xff,
  (value >>> 40) & 0xff,
  (value >>> 32) & 0xff,
  (value >>> 24) & 0xff,
  (value >>> 16) & 0xff,
  (value >>> 8) & 0xff,
  value & 0xff,
];

List<int> _frame(Uint8List value) => [
  (value.length >>> 24) & 0xff,
  (value.length >>> 16) & 0xff,
  (value.length >>> 8) & 0xff,
  value.length & 0xff,
  ...value,
];

final class _Api implements BetaMlsNativeApi {
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
