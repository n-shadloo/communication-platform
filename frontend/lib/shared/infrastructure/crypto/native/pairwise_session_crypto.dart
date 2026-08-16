import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/pairwise_crypto_port.dart';
import 'package:communication_platform/core/application/ports/pairwise_session_crypto_port.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/verified_bundle_request.dart';

final class NativePairwiseSessionCrypto implements PairwiseSessionCryptoPort {
  const NativePairwiseSessionCrypto(this.crypto);

  final PairwiseCryptoPort crypto;

  @override
  Future<Result<PairwisePublicHeaderInspection>> inspectPublicHeader({
    required Uint8List envelope,
  }) async {
    try {
      _validateEnvelope(envelope);
      final response = await _call(
        PairwiseCryptoOperation.inspectPublicHeader,
        (_Writer()..frame(envelope)).takeBytes(),
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      final reader = _Reader(value.body);
      final kind = reader.u8();
      final sessionId = reader.take(16);
      if (!reader.finished || kind > 1) {
        return _malformed();
      }
      return Result.success(
        PairwisePublicHeaderInspection(
          kind: PairwisePublicEnvelopeKind.values[kind],
          sessionId: sessionId,
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<PairwiseInitiationResult>> initiate({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List senderDeviceId,
    required Uint8List recipientUserId,
    required Uint8List recipientDeviceId,
    required Uint8List recipientSelfSigningPublic,
    required ClaimedPrekeyBundle verifiedBundle,
    required Uint8List innerPayload,
    required int otherSessionsSkippedKeys,
    Uint8List? repairAuthorization,
  }) async {
    try {
      _validateDayAndSkipped(unixDay, otherSessionsSkippedKeys);
      _exact(senderDeviceId, 16);
      _exact(recipientUserId, 16);
      _exact(recipientDeviceId, 16);
      _exact(recipientSelfSigningPublic, 32);
      if (repairAuthorization != null) {
        _exact(repairAuthorization, 88);
      }
      final bundleDeviceId = _uuidBytes(verifiedBundle.deviceId);
      if (!_same(bundleDeviceId, recipientDeviceId)) {
        return _integrityFailure();
      }
      final bundle = encodeVerifiedClaimedBundleRequest(
        userId: recipientUserId,
        deviceId: recipientDeviceId,
        selfSigningPublic: recipientSelfSigningPublic,
        bundle: verifiedBundle,
      );
      final writer = _Writer()
        ..frame(deviceState)
        ..u32(unixDay)
        ..bytes(senderDeviceId)
        ..bytes(recipientDeviceId)
        ..frame(bundle);
      _writeOptionalClassicalOneTime(writer, verifiedBundle);
      _writeOptionalPqOneTime(writer, verifiedBundle);
      writer
        ..frame(repairAuthorization ?? Uint8List(0))
        ..frame(innerPayload)
        ..u32(otherSessionsSkippedKeys);
      final response = await _call(
        PairwiseCryptoOperation.initiate,
        writer.takeBytes(),
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      final reader = _Reader(value.body);
      final stateBytes = reader.frame();
      final skipped = reader.u32();
      final envelope = reader.frame();
      final sessionId = reader.take(16);
      final priority = reader.u8();
      if (!reader.finished || priority > 1) {
        return _malformed();
      }
      return Result.success(
        PairwiseInitiationResult(
          prepared: PreparedPairwiseEnvelope(
            ciphertext: envelope,
            nextSession: PairwiseSessionState(
              sessionId: sessionId,
              opaqueState: stateBytes,
              skippedKeyCount: skipped,
            ),
          ),
          priority: SimultaneousInitiationPriority.values[priority],
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<PairwiseInitialSenderProjection>> probeInitial({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required Uint8List envelope,
  }) async {
    try {
      _validateDayAndSkipped(unixDay, 0);
      _exact(recipientDeviceId, 16);
      _validateEnvelope(envelope);
      final payload =
          (_Writer()
                ..frame(deviceState)
                ..u32(unixDay)
                ..bytes(recipientDeviceId)
                ..frame(envelope))
              .takeBytes();
      final response = await _call(
        PairwiseCryptoOperation.probeInitial,
        payload,
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      final reader = _Reader(value.body);
      final senderUserId = reader.take(16);
      final senderDeviceId = reader.take(16);
      final senderIk = reader.take(64);
      final registrationId = reader.u32();
      final bundleVersion = reader.u32();
      final repairPresent = reader.boolean();
      final replacedSessionId = repairPresent ? reader.take(16) : null;
      final probeToken = reader.take(32);
      if (!reader.finished) {
        return _malformed();
      }
      return Result.success(
        PairwiseInitialSenderProjection(
          senderUserId: senderUserId,
          senderDeviceId: senderDeviceId,
          senderIdentityPublic: senderIk,
          senderRegistrationId: registrationId,
          senderBundleVersion: bundleVersion,
          opaqueProbe: probeToken,
          replacedSessionId: replacedSessionId,
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<AcceptedPairwiseInitial>> acceptVerifiedInitial({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required Uint8List envelope,
    required PairwiseInitialSenderProjection probe,
    required PeerPublicDevice authenticatedSenderDevice,
    required int otherSessionsSkippedKeys,
    PairwiseSessionState? existingPrimarySession,
    PairwiseSessionState? replacedSession,
  }) async {
    try {
      _validateDayAndSkipped(unixDay, otherSessionsSkippedKeys);
      _exact(recipientDeviceId, 16);
      _validateEnvelope(envelope);
      final senderDeviceId = _uuidBytes(authenticatedSenderDevice.deviceId);
      if (!_same(senderDeviceId, probe.senderDeviceId) ||
          authenticatedSenderDevice.isUnsigned ||
          authenticatedSenderDevice.registrationId !=
              probe.senderRegistrationId ||
          authenticatedSenderDevice.bundleVersion == null ||
          authenticatedSenderDevice.bundleVersion! <
              probe.senderBundleVersion ||
          !_same(
            authenticatedSenderDevice.identityPublic,
            probe.senderIdentityPublic,
          ) ||
          probe.isRepairReplacement != (replacedSession != null) ||
          (replacedSession != null &&
              !_same(replacedSession.sessionId, probe.replacedSessionId!)) ||
          (existingPrimarySession != null && probe.isRepairReplacement)) {
        return _integrityFailure();
      }
      final senderProjection = _encodeAuthenticatedSenderProjection(
        probe,
        authenticatedSenderDevice,
      );
      final writer = _Writer()
        ..frame(deviceState)
        ..u32(unixDay)
        ..bytes(recipientDeviceId)
        ..frame(envelope)
        ..bytes(probe.opaqueProbe)
        ..frame(senderProjection)
        ..frame(existingPrimarySession?.opaqueState ?? Uint8List(0))
        ..frame(replacedSession?.opaqueState ?? Uint8List(0))
        ..u32(otherSessionsSkippedKeys);
      final response = await _call(
        PairwiseCryptoOperation.acceptVerifiedInitial,
        writer.takeBytes(),
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      final reader = _Reader(value.body);
      final nextDeviceState = reader.frame();
      final sessionState = reader.frame();
      final skipped = reader.u32();
      final opened = reader.frame();
      final replayMarker = reader.take(32);
      final classicalId = _optionalKeyId(reader.u32());
      final pqId = _optionalKeyId(reader.u32());
      final disposition = reader.u8();
      final updatedExistingState = reader.frame();
      final replacedPresent = reader.boolean();
      final replacedSessionId = replacedPresent ? reader.take(16) : null;
      final sessionId = reader.take(16);
      final referencedSignedPrekeyId = reader.u32();
      final referencedPqSignedPrekeyId = reader.u32();
      final parsedDisposition = disposition > 1
          ? null
          : PairwiseSessionDisposition.values[disposition];
      final mustUpdateExisting =
          existingPrimarySession != null &&
          parsedDisposition == PairwiseSessionDisposition.primary;
      if (!reader.finished ||
          parsedDisposition == null ||
          (existingPrimarySession == null &&
              parsedDisposition != PairwiseSessionDisposition.primary) ||
          replacedPresent != probe.isRepairReplacement ||
          (replacedPresent &&
              !_same(replacedSessionId!, probe.replacedSessionId!)) ||
          !_validKeyId(referencedSignedPrekeyId) ||
          !_validKeyId(referencedPqSignedPrekeyId) ||
          updatedExistingState.isNotEmpty != mustUpdateExisting) {
        return _malformed();
      }
      return Result.success(
        AcceptedPairwiseInitial(
          nextDeviceState: nextDeviceState,
          nextSession: PairwiseSessionState(
            sessionId: sessionId,
            opaqueState: sessionState,
            skippedKeyCount: skipped,
          ),
          senderUserId: probe.senderUserId,
          senderDeviceId: probe.senderDeviceId,
          openedPayload: opened,
          replayMarker: replayMarker,
          disposition: parsedDisposition,
          referencedSignedPrekeyId: referencedSignedPrekeyId,
          referencedPqSignedPrekeyId: referencedPqSignedPrekeyId,
          consumedOneTimePrekeyId: classicalId,
          consumedPqOneTimePrekeyId: pqId,
          replacedSessionId: replacedSessionId,
          updatedExistingSession: updatedExistingState.isEmpty
              ? null
              : PairwiseSessionState(
                  sessionId: existingPrimarySession!.sessionId,
                  opaqueState: updatedExistingState,
                  skippedKeyCount: existingPrimarySession.skippedKeyCount,
                ),
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<PreparedPairwiseEnvelope>> encrypt({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required Uint8List innerPayload,
    required int otherSessionsSkippedKeys,
  }) => _encryptLike(
    operation: PairwiseCryptoOperation.ratchetEncrypt,
    deviceState: deviceState,
    unixDay: unixDay,
    recipientDeviceId: recipientDeviceId,
    session: session,
    innerPayload: innerPayload,
    otherSessionsSkippedKeys: otherSessionsSkippedKeys,
  );

  @override
  Future<Result<PreparedPairwiseEnvelope>> createAuthenticatedRepairRequest({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required int otherSessionsSkippedKeys,
  }) => _encryptLike(
    operation: PairwiseCryptoOperation.createAuthenticatedRepairRequest,
    deviceState: deviceState,
    unixDay: unixDay,
    recipientDeviceId: recipientDeviceId,
    session: session,
    otherSessionsSkippedKeys: otherSessionsSkippedKeys,
  );

  Future<Result<PreparedPairwiseEnvelope>> _encryptLike({
    required PairwiseCryptoOperation operation,
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required int otherSessionsSkippedKeys,
    Uint8List? innerPayload,
  }) async {
    try {
      _validateSkipped(session, otherSessionsSkippedKeys);
      _validateDayAndSkipped(unixDay, otherSessionsSkippedKeys);
      _exact(recipientDeviceId, 16);
      final writer = _Writer()
        ..frame(deviceState)
        ..u32(unixDay)
        ..bytes(recipientDeviceId)
        ..frame(session.opaqueState);
      if (operation == PairwiseCryptoOperation.ratchetEncrypt) {
        writer.frame(innerPayload!);
      }
      writer.u32(otherSessionsSkippedKeys);
      final response = await _call(operation, writer.takeBytes());
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      return Result.success(
        _parsePreparedEnvelope(value.body, session.sessionId),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<PairwiseRatchetDecryptResult>> decrypt({
    required Uint8List deviceState,
    required int unixDay,
    required Uint8List recipientDeviceId,
    required PairwiseSessionState session,
    required Uint8List envelope,
    required int otherSessionsSkippedKeys,
  }) async {
    try {
      _validateSkipped(session, otherSessionsSkippedKeys);
      _validateDayAndSkipped(unixDay, otherSessionsSkippedKeys);
      _exact(recipientDeviceId, 16);
      _validateEnvelope(envelope);
      final payload =
          (_Writer()
                ..frame(deviceState)
                ..u32(unixDay)
                ..bytes(recipientDeviceId)
                ..frame(session.opaqueState)
                ..frame(envelope)
                ..u32(otherSessionsSkippedKeys))
              .takeBytes();
      final response = await _call(
        PairwiseCryptoOperation.ratchetDecrypt,
        payload,
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome == PairwiseCryptoOutcome.repairRequired) {
        if (value.body.length != 1 || value.body.first != 1) {
          return _malformed();
        }
        return Result.success(
          PairwiseRatchetRepairRequired(sessionId: session.sessionId),
        );
      }
      final reader = _Reader(value.body);
      final nextState = reader.frame();
      final skipped = reader.u32();
      final opened = reader.frame();
      final replayMarker = reader.take(32);
      final payloadKind = reader.u8();
      final sessionId = reader.take(16);
      final referencedSignedPrekeyId = _optionalKeyId(reader.u32());
      final referencedPqSignedPrekeyId = _optionalKeyId(reader.u32());
      if (!reader.finished ||
          payloadKind > 1 ||
          !_same(sessionId, session.sessionId) ||
          referencedSignedPrekeyId != null ||
          referencedPqSignedPrekeyId != null) {
        return _malformed();
      }
      return Result.success(
        PairwiseRatchetDecryption(
          nextSession: PairwiseSessionState(
            sessionId: sessionId,
            opaqueState: nextState,
            skippedKeyCount: skipped,
          ),
          openedPayload: opened,
          replayMarker: replayMarker,
          payloadKind: PairwiseOpenedPayloadKind.values[payloadKind],
          referencedSignedPrekeyId: referencedSignedPrekeyId,
          referencedPqSignedPrekeyId: referencedPqSignedPrekeyId,
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  @override
  Future<Result<AuthenticatedRepairAuthorization>>
  consumeAuthenticatedRepairRequest({
    required Uint8List deviceState,
    required int unixDay,
    required PairwiseSessionState session,
  }) async {
    try {
      _validateDayAndSkipped(unixDay, 0);
      final payload =
          (_Writer()
                ..frame(deviceState)
                ..u32(unixDay)
                ..frame(session.opaqueState))
              .takeBytes();
      final response = await _call(
        PairwiseCryptoOperation.consumeAuthenticatedRepairRequest,
        payload,
      );
      if (response case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final value = (response as Success<PairwiseCryptoResponse>).value;
      if (value.outcome != PairwiseCryptoOutcome.ok) {
        return _integrityFailure();
      }
      final reader = _Reader(value.body);
      final nextState = reader.frame();
      final skipped = reader.u32();
      final authorization = reader.frame();
      final sessionId = reader.take(16);
      if (!reader.finished ||
          authorization.length != 88 ||
          !_same(sessionId, session.sessionId)) {
        return _malformed();
      }
      return Result.success(
        AuthenticatedRepairAuthorization(
          nextSession: PairwiseSessionState(
            sessionId: sessionId,
            opaqueState: nextState,
            skippedKeyCount: skipped,
          ),
          authorization: authorization,
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  Future<Result<PairwiseCryptoResponse>> _call(
    PairwiseCryptoOperation operation,
    Uint8List payload,
  ) => crypto.pairwiseOperation(operation: operation, payload: payload);
}

PreparedPairwiseEnvelope _parsePreparedEnvelope(
  Uint8List body,
  Uint8List expectedSessionId,
) {
  final reader = _Reader(body);
  final state = reader.frame();
  final skipped = reader.u32();
  final envelope = reader.frame();
  final sessionId = reader.take(16);
  if (!reader.finished || !_same(sessionId, expectedSessionId)) {
    throw const PairwiseCryptoFormatException();
  }
  return PreparedPairwiseEnvelope(
    ciphertext: envelope,
    nextSession: PairwiseSessionState(
      sessionId: sessionId,
      opaqueState: state,
      skippedKeyCount: skipped,
    ),
  );
}

Uint8List _encodeAuthenticatedSenderProjection(
  PairwiseInitialSenderProjection probe,
  PeerPublicDevice device,
) =>
    (_Writer()
          ..bytes(ascii.encode('CPSAV001'))
          ..bytes(probe.senderUserId)
          ..bytes(probe.senderDeviceId)
          ..bytes(device.identityPublic)
          ..u32(device.registrationId)
          ..u32(device.bundleVersion!))
        .takeBytes();

void _writeOptionalClassicalOneTime(
  _Writer writer,
  ClaimedPrekeyBundle bundle,
) {
  final id = bundle.oneTimePrekeyId;
  final public = bundle.oneTimePrekeyPublic;
  if ((id == null) != (public == null) ||
      (id != null && (!_validKeyId(id) || public!.length != 32))) {
    throw const PairwiseCryptoFormatException();
  }
  writer.boolean(id != null);
  if (id != null) {
    writer
      ..u32(id)
      ..bytes(public!);
  }
}

void _writeOptionalPqOneTime(_Writer writer, ClaimedPrekeyBundle bundle) {
  final id = bundle.pqOneTimePrekeyId;
  final public = bundle.pqOneTimePrekeyPublic;
  if ((id == null) != (public == null) ||
      (id != null && (!_validKeyId(id) || public!.length != 1184))) {
    throw const PairwiseCryptoFormatException();
  }
  writer.boolean(id != null);
  if (id != null) {
    writer
      ..u32(id)
      ..bytes(public!);
  }
}

int? _optionalKeyId(int value) {
  if (value == 0xffffffff) {
    return null;
  }
  if (!_validKeyId(value)) {
    throw const PairwiseCryptoFormatException();
  }
  return value;
}

bool _validKeyId(int value) => value >= 0 && value <= 0x7fffffff;

void _validateDayAndSkipped(int day, int skipped) {
  if (day < 0 || day > 0xffffffff || skipped < 0 || skipped > 20000) {
    throw const PairwiseCryptoFormatException();
  }
}

void _validateSkipped(PairwiseSessionState session, int otherSkipped) {
  _validateDayAndSkipped(0, otherSkipped);
  if (session.skippedKeyCount + otherSkipped >
      PairwiseTransportV1.maximumSkippedKeysPerAccount) {
    throw const PairwiseCryptoFormatException();
  }
}

void _validateEnvelope(Uint8List envelope) {
  if (!PairwiseTransportV1.envelopeBuckets.contains(envelope.length)) {
    throw const PairwiseCryptoFormatException();
  }
}

Uint8List _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  if (compact.length != 32 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
    throw const PairwiseCryptoFormatException();
  }
  return Uint8List.fromList([
    for (var index = 0; index < compact.length; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}

Uint8List _exact(Uint8List value, int length) {
  if (value.length != length) {
    throw const PairwiseCryptoFormatException();
  }
  return value;
}

Result<T> _integrityFailure<T>() => const Result.failure(
  SecurityFailure(SecurityFailureKind.integrityCheckFailed),
);

Result<T> _malformed<T>() => const Result.failure(
  SecurityFailure(SecurityFailureKind.malformedServerResponse),
);

final class _Writer {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void bytes(List<int> value) => _builder.add(value);

  void boolean(bool value) => _builder.addByte(value ? 1 : 0);

  void u32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const PairwiseCryptoFormatException();
    }
    final encoded = Uint8List(4);
    ByteData.sublistView(encoded).setUint32(0, value);
    bytes(encoded);
  }

  void frame(Uint8List value) {
    if (value.length > 2 * 1024 * 1024) {
      throw const PairwiseCryptoFormatException();
    }
    u32(value.length);
    bytes(value);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

final class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  var _offset = 0;

  bool get finished => _offset == _bytes.length;

  bool boolean() {
    final value = u8();
    if (value > 1) {
      throw const PairwiseCryptoFormatException();
    }
    return value == 1;
  }

  int u8() => take(1).first;

  int u32() => ByteData.sublistView(take(4)).getUint32(0);

  Uint8List frame() {
    final length = u32();
    if (length > 2 * 1024 * 1024) {
      throw const PairwiseCryptoFormatException();
    }
    return take(length);
  }

  Uint8List take(int length) {
    final end = _offset + length;
    if (length < 0 || end < _offset || end > _bytes.length) {
      throw const PairwiseCryptoFormatException();
    }
    final value = Uint8List.fromList(_bytes.sublist(_offset, end));
    _offset = end;
    return value;
  }
}

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
