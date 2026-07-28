import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/identity_crypto_ffi.dart';

final class IdentityCryptoNativeSession {
  const IdentityCryptoNativeSession({required this.api});

  final IdentityCryptoNativeApi api;

  Result<void> verifyIdentity(Uint8List userId, PeerIdentityPublic identity) {
    final input = BytesBuilder(copy: false)
      ..add(ascii.encode('CPIRV001'))
      ..add(userId)
      ..add(identity.masterPublic)
      ..add(identity.selfSigningPublic)
      ..add(identity.userSigningPublic)
      ..add(identity.masterSignature);
    return _void(api.operation(1, input.takeBytes()));
  }

  Result<void> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) {
    final pqPublic = bundle.pqSignedPrekeyPublic;
    final pqSignature = bundle.pqSignedPrekeySignature;
    final input = BytesBuilder(copy: false)
      ..add(ascii.encode('CPBRV001'))
      ..add(userId)
      ..add(deviceId)
      ..add(selfSigningPublic)
      ..add(bundle.identityPublic)
      ..add(_u32(bundle.signedPrekeyId))
      ..add(_sized(bundle.signedPrekeyPublic))
      ..add(bundle.signedPrekeySignature)
      ..addByte(pqPublic == null ? 0 : 1);
    if (pqPublic != null && pqSignature != null) {
      input
        ..add(_u32(bundle.pqSignedPrekeyId!))
        ..add(_sized(pqPublic))
        ..add(pqSignature);
    }
    input
      ..add(_u32(bundle.registrationId))
      ..add(_u32(bundle.bundleVersion))
      ..add(bundle.crossSignature);
    return _void(api.operation(2, input.takeBytes()));
  }

  Result<PeerDeviceLogInspection> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) {
    final input = BytesBuilder(copy: false)
      ..add(ascii.encode('CPDLR001'))
      ..add(userId)
      ..add(selfSigningPublic)
      ..addByte(requireCurrentLiveSet ? 1 : 0)
      ..add(_u32(liveDevices.length));
    for (final device in liveDevices) {
      final deviceId = _uuidBytes(device.deviceId);
      input
        ..add(deviceId)
        ..add(device.identityPublic)
        ..add(_u32(device.registrationId))
        ..addByte(device.crossSignature == null ? 0 : 1);
      if (device.crossSignature != null) {
        input.add(device.crossSignature!);
      }
      input.add(_u32(device.bundleVersion ?? 0));
    }
    input.add(record);
    return _value(
      api.operation(3, input.takeBytes()),
      PeerDeviceLogInspection.fromNative,
    );
  }

  Result<SafetyFingerprint> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) {
    final input = BytesBuilder(copy: false)
      ..add(ascii.encode('CPSFV001'))
      ..add(localUserId)
      ..add(localMasterPublic)
      ..add(peerUserId)
      ..add(peerMasterPublic);
    return _value(api.operation(4, input.takeBytes()), SafetyFingerprint.new);
  }

  Result<UserSigningAttestation> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _value(
    api.attest(localIdentity.opaqueBytes, peerUserId, peerMasterPublic),
    UserSigningAttestation.new,
  );

  Result<void> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) {
    final input = BytesBuilder(copy: false)
      ..add(ascii.encode('CPUAV001'))
      ..add(signerUserId)
      ..add(signerUserSigningPublic)
      ..add(peerUserId)
      ..add(peerMasterPublic)
      ..add(attestation.signature);
    return _void(api.operation(5, input.takeBytes()));
  }

  Result<void> _void(NativeBufferResult result) {
    if (result.statusCode != 0) {
      return Result.failure(
        enrollmentFailureFromNativeStatus(result.statusCode),
      );
    }
    if (result.bytes == null || result.bytes!.isNotEmpty) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    return const Result.success(null);
  }

  Result<T> _value<T>(NativeBufferResult result, T Function(Uint8List) decode) {
    if (result.statusCode != 0) {
      return Result.failure(
        enrollmentFailureFromNativeStatus(result.statusCode),
      );
    }
    final bytes = result.bytes;
    if (bytes == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    try {
      return Result.success(decode(bytes));
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }
}

Uint8List _u32(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw const IdentityProtocolFormatException();
  }
  return Uint8List(4)..buffer.asByteData().setUint32(0, value);
}

Uint8List _sized(Uint8List value) =>
    Uint8List.fromList(<int>[..._u32(value.length), ...value]);

Uint8List _uuidBytes(String value) {
  final compact = value.replaceAll('-', '');
  if (compact.length != 32 || !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
    throw const IdentityProtocolFormatException();
  }
  return Uint8List.fromList([
    for (var index = 0; index < compact.length; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}
