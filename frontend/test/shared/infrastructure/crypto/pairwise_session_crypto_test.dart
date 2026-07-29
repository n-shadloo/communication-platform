import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/pairwise_crypto_port.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/pairwise_session_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public routing is parsed only by native operation 17', () async {
    final sessionId = _bytes(16, 4);
    final raw = _Raw()
      ..response = PairwiseCryptoResponse(
        operation: PairwiseCryptoOperation.inspectPublicHeader,
        outcome: PairwiseCryptoOutcome.ok,
        body: Uint8List.fromList([1, ...sessionId]),
      );
    final envelope = _bytes(1024, 3);

    final result = await NativePairwiseSessionCrypto(
      raw,
    ).inspectPublicHeader(envelope: envelope);

    expect(result, isA<Success<PairwisePublicHeaderInspection>>());
    final inspection =
        (result as Success<PairwisePublicHeaderInspection>).value;
    expect(inspection.kind, PairwisePublicEnvelopeKind.initial);
    expect(inspection.sessionId, sessionId);
    expect(raw.operation, PairwiseCryptoOperation.inspectPublicHeader);
    expect(_Reader(raw.payload!).frame(), envelope);
  });

  test(
    'initiation rejects missing signed PQ material without calling native',
    () async {
      final raw = _Raw();
      final crypto = NativePairwiseSessionCrypto(raw);

      final result = await crypto.initiate(
        deviceState: _bytes(64, 1),
        unixDay: 10,
        senderDeviceId: _bytes(16, 2),
        recipientUserId: _bytes(16, 3),
        recipientDeviceId: _uuidBytes(_deviceId),
        recipientSelfSigningPublic: _bytes(32, 4),
        verifiedBundle: _bundle(includePq: false),
        innerPayload: _bytes(8, 5),
        otherSessionsSkippedKeys: 0,
      );

      expect(result, isA<FailureResult<PairwiseInitiationResult>>());
      expect(raw.calls, 0);
    },
  );

  test(
    'initiation frames the mandatory verified PQ bundle for native recheck',
    () async {
      final sessionId = _bytes(16, 7);
      final raw = _Raw()
        ..response = PairwiseCryptoResponse(
          operation: PairwiseCryptoOperation.initiate,
          outcome: PairwiseCryptoOutcome.ok,
          body:
              (_Writer()
                    ..frame(_bytes(80, 1))
                    ..u32(0)
                    ..frame(_bytes(1024, 2))
                    ..bytes(sessionId)
                    ..u8(0))
                  .takeBytes(),
        );

      final result = await NativePairwiseSessionCrypto(raw).initiate(
        deviceState: _bytes(64, 1),
        unixDay: 10,
        senderDeviceId: _bytes(16, 2),
        recipientUserId: _bytes(16, 3),
        recipientDeviceId: _uuidBytes(_deviceId),
        recipientSelfSigningPublic: _bytes(32, 4),
        verifiedBundle: _bundle(
          includePq: true,
          registrationId: 0,
          signedPrekeyId: 0,
          pqSignedPrekeyId: 0,
        ),
        innerPayload: _bytes(8, 5),
        otherSessionsSkippedKeys: 0,
      );

      expect(result, isA<Success<PairwiseInitiationResult>>());
      expect(raw.operation, PairwiseCryptoOperation.initiate);
      expect(_contains(raw.payload!, 'CPBRV001'.codeUnits), isTrue);
      expect(
        (result as Success<PairwiseInitiationResult>).value.prepared.ciphertext,
        hasLength(1024),
      );
    },
  );

  test(
    'accept uses authenticated live-device projection and returns SPK references',
    () async {
      final sessionId = _bytes(16, 9);
      final raw = _Raw()
        ..response = PairwiseCryptoResponse(
          operation: PairwiseCryptoOperation.acceptVerifiedInitial,
          outcome: PairwiseCryptoOutcome.ok,
          body:
              (_Writer()
                    ..frame(_bytes(80, 1))
                    ..frame(_bytes(96, 2))
                    ..u32(0)
                    ..frame(_bytes(5, 3))
                    ..bytes(_bytes(32, 4))
                    ..u32(0xffffffff)
                    ..u32(0xffffffff)
                    ..u8(0)
                    ..frame(Uint8List(0))
                    ..u8(0)
                    ..bytes(sessionId)
                    ..u32(7)
                    ..u32(8))
                  .takeBytes(),
        );
      final probe = PairwiseInitialSenderProjection(
        senderUserId: _bytes(16, 6),
        senderDeviceId: _uuidBytes(_deviceId),
        senderIdentityPublic: _bytes(64, 7),
        senderRegistrationId: 9,
        senderBundleVersion: 2,
        opaqueProbe: _bytes(32, 8),
      );

      final result = await NativePairwiseSessionCrypto(raw)
          .acceptVerifiedInitial(
            deviceState: _bytes(64, 1),
            unixDay: 10,
            recipientDeviceId: _bytes(16, 2),
            envelope: _bytes(1024, 3),
            probe: probe,
            authenticatedSenderDevice: PeerPublicDevice(
              deviceId: _deviceId,
              identityPublic: _bytes(64, 7),
              registrationId: 9,
              crossSignature: _bytes(64, 5),
              bundleVersion: 3,
            ),
            otherSessionsSkippedKeys: 0,
          );

      expect(result, isA<Success<AcceptedPairwiseInitial>>());
      expect(_contains(raw.payload!, 'CPSAV001'.codeUnits), isTrue);
      expect(_contains(raw.payload!, 'CPBRV001'.codeUnits), isFalse);
      final accepted = (result as Success<AcceptedPairwiseInitial>).value;
      expect(accepted.referencedSignedPrekeyId, 7);
      expect(accepted.referencedPqSignedPrekeyId, 8);
    },
  );

  test('accept rejects a probe from a future sender bundle version', () async {
    final raw = _Raw();
    final result = await NativePairwiseSessionCrypto(raw).acceptVerifiedInitial(
      deviceState: _bytes(64, 1),
      unixDay: 10,
      recipientDeviceId: _bytes(16, 2),
      envelope: _bytes(1024, 3),
      probe: PairwiseInitialSenderProjection(
        senderUserId: _bytes(16, 6),
        senderDeviceId: _uuidBytes(_deviceId),
        senderIdentityPublic: _bytes(64, 7),
        senderRegistrationId: 9,
        senderBundleVersion: 3,
        opaqueProbe: _bytes(32, 8),
      ),
      authenticatedSenderDevice: PeerPublicDevice(
        deviceId: _deviceId,
        identityPublic: _bytes(64, 7),
        registrationId: 9,
        crossSignature: _bytes(64, 5),
        bundleVersion: 2,
      ),
      otherSessionsSkippedKeys: 0,
    );

    expect(result, isA<FailureResult<AcceptedPairwiseInitial>>());
    expect(raw.operation, isNull);
  });

  test('encrypt rejects a native session-id substitution', () async {
    final session = PairwiseSessionState(
      sessionId: _bytes(16, 7),
      opaqueState: _bytes(80, 8),
      skippedKeyCount: 0,
    );
    final raw = _Raw()
      ..response = PairwiseCryptoResponse(
        operation: PairwiseCryptoOperation.ratchetEncrypt,
        outcome: PairwiseCryptoOutcome.ok,
        body:
            (_Writer()
                  ..frame(_bytes(80, 1))
                  ..u32(0)
                  ..frame(_bytes(1024, 2))
                  ..bytes(_bytes(16, 99)))
                .takeBytes(),
      );

    final result = await NativePairwiseSessionCrypto(raw).encrypt(
      deviceState: _bytes(64, 1),
      unixDay: 10,
      recipientDeviceId: _bytes(16, 2),
      session: session,
      innerPayload: _bytes(8, 3),
      otherSessionsSkippedKeys: 0,
    );

    expect(result, isA<FailureResult<PreparedPairwiseEnvelope>>());
  });

  test('accept rejects impossible disposition/update combinations', () async {
    final probe = PairwiseInitialSenderProjection(
      senderUserId: _bytes(16, 6),
      senderDeviceId: _uuidBytes(_deviceId),
      senderIdentityPublic: _bytes(64, 7),
      senderRegistrationId: 9,
      senderBundleVersion: 2,
      opaqueProbe: _bytes(32, 8),
    );
    final device = PeerPublicDevice(
      deviceId: _deviceId,
      identityPublic: _bytes(64, 7),
      registrationId: 9,
      crossSignature: _bytes(64, 5),
      bundleVersion: 2,
    );
    final existing = PairwiseSessionState(
      sessionId: _bytes(16, 20),
      opaqueState: _bytes(80, 21),
      skippedKeyCount: 0,
    );

    for (final malformed in [
      (disposition: 1, existing: null as PairwiseSessionState?),
      (disposition: 0, existing: existing),
    ]) {
      final raw = _Raw()
        ..response = PairwiseCryptoResponse(
          operation: PairwiseCryptoOperation.acceptVerifiedInitial,
          outcome: PairwiseCryptoOutcome.ok,
          body: _acceptedBody(disposition: malformed.disposition),
        );
      final result = await NativePairwiseSessionCrypto(raw)
          .acceptVerifiedInitial(
            deviceState: _bytes(64, 1),
            unixDay: 10,
            recipientDeviceId: _bytes(16, 2),
            envelope: _bytes(1024, 3),
            probe: probe,
            authenticatedSenderDevice: device,
            existingPrimarySession: malformed.existing,
            otherSessionsSkippedKeys: 0,
          );
      expect(result, isA<FailureResult<AcceptedPairwiseInitial>>());
    }
  });

  test('repair authorization is exactly 88 bytes', () async {
    final raw = _Raw();
    final result = await NativePairwiseSessionCrypto(raw).initiate(
      deviceState: _bytes(64, 1),
      unixDay: 10,
      senderDeviceId: _bytes(16, 2),
      recipientUserId: _bytes(16, 3),
      recipientDeviceId: _uuidBytes(_deviceId),
      recipientSelfSigningPublic: _bytes(32, 4),
      verifiedBundle: _bundle(includePq: true),
      repairAuthorization: _bytes(87, 5),
      innerPayload: _bytes(8, 6),
      otherSessionsSkippedKeys: 0,
    );

    expect(result, isA<FailureResult<PairwiseInitiationResult>>());
    expect(raw.operation, isNull);
  });

  test('consume rejects a malformed native repair authorization', () async {
    final session = PairwiseSessionState(
      sessionId: _bytes(16, 7),
      opaqueState: _bytes(80, 8),
      skippedKeyCount: 0,
    );
    final raw = _Raw()
      ..response = PairwiseCryptoResponse(
        operation: PairwiseCryptoOperation.consumeAuthenticatedRepairRequest,
        outcome: PairwiseCryptoOutcome.ok,
        body:
            (_Writer()
                  ..frame(_bytes(80, 1))
                  ..u32(0)
                  ..frame(_bytes(87, 2))
                  ..bytes(session.sessionId))
                .takeBytes(),
      );

    final result = await NativePairwiseSessionCrypto(raw)
        .consumeAuthenticatedRepairRequest(
          deviceState: _bytes(64, 1),
          unixDay: 10,
          session: session,
        );

    expect(result, isA<FailureResult<AuthenticatedRepairAuthorization>>());
  });

  test('repair-required decrypt returns no candidate state mutation', () async {
    final raw = _Raw()
      ..response = PairwiseCryptoResponse(
        operation: PairwiseCryptoOperation.ratchetDecrypt,
        outcome: PairwiseCryptoOutcome.repairRequired,
        body: Uint8List.fromList([1]),
      );
    final session = PairwiseSessionState(
      sessionId: _bytes(16, 7),
      opaqueState: _bytes(80, 8),
      skippedKeyCount: 4,
    );

    final result = await NativePairwiseSessionCrypto(raw).decrypt(
      deviceState: _bytes(64, 1),
      unixDay: 10,
      recipientDeviceId: _bytes(16, 2),
      session: session,
      envelope: _bytes(1024, 3),
      otherSessionsSkippedKeys: 19996,
    );

    expect(result, isA<Success<PairwiseRatchetDecryptResult>>());
    expect(
      (result as Success<PairwiseRatchetDecryptResult>).value,
      isA<PairwiseRatchetRepairRequired>(),
    );
    final reader = _Reader(raw.payload!);
    expect(reader.frame(), _bytes(64, 1));
    expect(reader.u32(), 10);
  });
}

const _deviceId = '22222222-2222-4222-8222-222222222222';

ClaimedPrekeyBundle _bundle({
  required bool includePq,
  int registrationId = 9,
  int signedPrekeyId = 1,
  int pqSignedPrekeyId = 2,
}) => ClaimedPrekeyBundle(
  deviceId: _deviceId,
  registrationId: registrationId,
  identityPublic: _bytes(64, 7),
  signedPrekeyId: signedPrekeyId,
  signedPrekeyPublic: _bytes(32, 8),
  signedPrekeySignature: _bytes(64, 9),
  crossSignature: _bytes(64, 10),
  bundleVersion: 2,
  pqSignedPrekeyId: includePq ? pqSignedPrekeyId : null,
  pqSignedPrekeyPublic: includePq ? _bytes(1184, 11) : null,
  pqSignedPrekeySignature: includePq ? _bytes(64, 12) : null,
);

final class _Raw implements PairwiseCryptoPort {
  PairwiseCryptoResponse? response;
  PairwiseCryptoOperation? operation;
  Uint8List? payload;
  var calls = 0;

  @override
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  }) async {
    calls += 1;
    this.operation = operation;
    this.payload = Uint8List.fromList(payload);
    return Result.success(response!);
  }
}

final class _Writer {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void bytes(List<int> value) => _builder.add(value);

  void u8(int value) => _builder.addByte(value);

  void u32(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value);
    _builder.add(bytes);
  }

  void frame(Uint8List value) {
    u32(value.length);
    bytes(value);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

final class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  var offset = 0;

  int u32() {
    final result = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    offset += 4;
    return result;
  }

  Uint8List frame() {
    final length = u32();
    final result = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return result;
  }
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var offset = 0; offset <= haystack.length - needle.length; offset += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      matches &= haystack[offset + index] == needle[index];
    }
    if (matches) return true;
  }
  return false;
}

Uint8List _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  return Uint8List.fromList([
    for (var index = 0; index < compact.length; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}

Uint8List _acceptedBody({required int disposition}) =>
    (_Writer()
          ..frame(_bytes(80, 1))
          ..frame(_bytes(96, 2))
          ..u32(0)
          ..frame(_bytes(5, 3))
          ..bytes(_bytes(32, 4))
          ..u32(0xffffffff)
          ..u32(0xffffffff)
          ..u8(disposition)
          ..frame(Uint8List(0))
          ..u8(0)
          ..bytes(_bytes(16, 9))
          ..u32(7)
          ..u32(8))
        .takeBytes();

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));
