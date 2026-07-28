import 'dart:convert';
import 'dart:typed_data';

const _devicePackageMagic = <int>[67, 80, 68, 86, 86, 48, 48, 49];
const _identityPackageMagic = <int>[67, 80, 73, 68, 86, 48, 48, 49];
const _deviceLogInspectionBytes = 72;
const _deviceLogBytes = 256;
const _maxOpaquePackageBytes = 1024 * 1024;

/// A native-generated device package. The package bytes are opaque to Dart;
/// [public] is the non-secret registration projection used by the REST DTO.
final class DeviceKeyPackage {
  DeviceKeyPackage._({required Uint8List opaqueBytes, required this.public})
    : opaqueBytes = Uint8List.fromList(opaqueBytes);

  factory DeviceKeyPackage.fromNative(Uint8List bytes) {
    final reader = _BinaryReader(bytes);
    if (!_same(reader.take(8), _devicePackageMagic)) {
      throw const EnrollmentCryptoFormatException();
    }
    final userId = reader.take(16);
    final registrationId = reader.u32();
    final spkId = reader.u32();
    final pqSpkId = reader.u32();
    final classicalCount = reader.u16();
    final pqCount = reader.u16();
    if (classicalCount == 0 ||
        classicalCount > 200 ||
        pqCount == 0 ||
        pqCount > 100) {
      throw const EnrollmentCryptoFormatException();
    }
    final ikPub = reader.take(64);
    final spkPub = reader.take(32);
    final spkSig = reader.take(64);
    final pqSpkPub = reader.take(1184);
    final pqSpkSig = reader.take(64);
    final fingerprint = reader.take(32);
    final otpks = <DeviceOneTimePrekey>[];
    for (var index = 0; index < classicalCount; index += 1) {
      otpks.add(
        DeviceOneTimePrekey(keyId: reader.u32(), publicKey: reader.take(32)),
      );
    }
    final pqOtpks = <DeviceOneTimePrekey>[];
    for (var index = 0; index < pqCount; index += 1) {
      pqOtpks.add(
        DeviceOneTimePrekey(keyId: reader.u32(), publicKey: reader.take(1184)),
      );
    }
    // The trailing native-owned key state is deliberately not decoded.
    if (reader.remaining <= 0 || bytes.length > _maxOpaquePackageBytes) {
      throw const EnrollmentCryptoFormatException();
    }
    return DeviceKeyPackage._(
      opaqueBytes: bytes,
      public: DeviceRegistrationPublic(
        userId: userId,
        registrationId: registrationId,
        spkId: spkId,
        spkPub: spkPub,
        spkSig: spkSig,
        ikPub: ikPub,
        pqSpkId: pqSpkId,
        pqSpkPub: pqSpkPub,
        pqSpkSig: pqSpkSig,
        otpks: otpks,
        pqOtpks: pqOtpks,
        fingerprint: fingerprint,
      ),
    );
  }

  final Uint8List opaqueBytes;
  final DeviceRegistrationPublic public;

  @override
  String toString() => 'DeviceKeyPackage(<redacted>)';
}

final class DeviceRegistrationPublic {
  DeviceRegistrationPublic({
    required Uint8List userId,
    required this.registrationId,
    required this.spkId,
    required Uint8List spkPub,
    required Uint8List spkSig,
    required Uint8List ikPub,
    required this.pqSpkId,
    required Uint8List pqSpkPub,
    required Uint8List pqSpkSig,
    required List<DeviceOneTimePrekey> otpks,
    required List<DeviceOneTimePrekey> pqOtpks,
    required Uint8List fingerprint,
  }) : userId = _copyExact(userId, 16),
       spkPub = _copyExact(spkPub, 32),
       spkSig = _copyExact(spkSig, 64),
       ikPub = _copyExact(ikPub, 64),
       pqSpkPub = _copyExact(pqSpkPub, 1184),
       pqSpkSig = _copyExact(pqSpkSig, 64),
       otpks = List<DeviceOneTimePrekey>.unmodifiable(otpks),
       pqOtpks = List<DeviceOneTimePrekey>.unmodifiable(pqOtpks),
       fingerprint = _copyExact(fingerprint, 32);

  final Uint8List userId;
  final int registrationId;
  final int spkId;
  final Uint8List spkPub;
  final Uint8List spkSig;
  final Uint8List ikPub;
  final int pqSpkId;
  final Uint8List pqSpkPub;
  final Uint8List pqSpkSig;
  final List<DeviceOneTimePrekey> otpks;
  final List<DeviceOneTimePrekey> pqOtpks;
  final Uint8List fingerprint;

  String get fingerprintBase64 => base64Encode(fingerprint);

  @override
  String toString() => 'DeviceRegistrationPublic(<redacted>)';
}

final class DeviceOneTimePrekey {
  DeviceOneTimePrekey({required this.keyId, required Uint8List publicKey})
    : publicKey = Uint8List.fromList(publicKey);

  final int keyId;
  final Uint8List publicKey;
}

/// Cross-signing identity projection plus opaque native private state.
final class IdentityKeyPackage {
  IdentityKeyPackage._({
    required Uint8List opaqueBytes,
    required Uint8List userId,
    required Uint8List masterPub,
    required Uint8List selfSigningPub,
    required Uint8List userSigningPub,
    required Uint8List masterSig,
    required Uint8List recoverySecretBytes,
    required Uint8List backup,
  }) : opaqueBytes = Uint8List.fromList(opaqueBytes),
       userId = _copyExact(userId, 16),
       masterPub = _copyExact(masterPub, 32),
       selfSigningPub = _copyExact(selfSigningPub, 32),
       userSigningPub = _copyExact(userSigningPub, 32),
       masterSig = _copyExact(masterSig, 64),
       recoverySecretBytes = Uint8List.fromList(recoverySecretBytes),
       backup = Uint8List.fromList(backup);

  factory IdentityKeyPackage.fromNative(Uint8List bytes) {
    final reader = _BinaryReader(bytes);
    if (!_same(reader.take(8), _identityPackageMagic)) {
      throw const EnrollmentCryptoFormatException();
    }
    final flags = reader.u8();
    if (flags & ~3 != 0) {
      throw const EnrollmentCryptoFormatException();
    }
    final userId = reader.take(16);
    final masterPub = reader.take(32);
    final selfSigningPub = reader.take(32);
    final userSigningPub = reader.take(32);
    final masterSig = reader.take(64);
    final recoveryLength = reader.u16();
    final backupLength = reader.u32();
    final privateLength = 96;
    reader.take(privateLength);
    final recovery = reader.take(recoveryLength);
    final backup = reader.take(backupLength);
    if (reader.remaining != 0 ||
        (flags & 1 != 0) != recovery.isNotEmpty ||
        (flags & 2 != 0) != backup.isNotEmpty ||
        bytes.length > _maxOpaquePackageBytes) {
      throw const EnrollmentCryptoFormatException();
    }
    final recoverySecretBytes = Uint8List.fromList(recovery);
    return IdentityKeyPackage._(
      opaqueBytes: bytes,
      userId: userId,
      masterPub: masterPub,
      selfSigningPub: selfSigningPub,
      userSigningPub: userSigningPub,
      masterSig: masterSig,
      recoverySecretBytes: recoverySecretBytes,
      backup: backup,
    );
  }

  final Uint8List opaqueBytes;
  final Uint8List userId;
  final Uint8List masterPub;
  final Uint8List selfSigningPub;
  final Uint8List userSigningPub;
  final Uint8List masterSig;
  final Uint8List recoverySecretBytes;
  final Uint8List backup;

  String? get recoverySecret => recoverySecretBytes.isEmpty
      ? null
      : utf8.decode(recoverySecretBytes, allowMalformed: false);

  bool get hasDisplayMaterial =>
      recoverySecretBytes.isNotEmpty && backup.isNotEmpty;

  @override
  String toString() => 'IdentityKeyPackage(<redacted>)';
}

final class DeviceLogInspection {
  DeviceLogInspection({
    required this.sequence,
    required Uint8List previousHash,
    required Uint8List recordHash,
  }) : previousHash = _copyExact(previousHash, 32),
       recordHash = _copyExact(recordHash, 32);

  factory DeviceLogInspection.fromNative(Uint8List bytes) {
    if (bytes.length != _deviceLogInspectionBytes) {
      throw const EnrollmentCryptoFormatException();
    }
    final data = ByteData.sublistView(bytes);
    return DeviceLogInspection(
      sequence: data.getUint64(0),
      previousHash: bytes.sublist(8, 40),
      recordHash: bytes.sublist(40, 72),
    );
  }

  final int sequence;
  final Uint8List previousHash;
  final Uint8List recordHash;

  Uint8List toNative() {
    final bytes = Uint8List(_deviceLogInspectionBytes);
    ByteData.sublistView(bytes).setUint64(0, sequence);
    bytes
      ..setRange(8, 40, previousHash)
      ..setRange(40, 72, recordHash);
    return bytes;
  }

  @override
  String toString() => 'DeviceLogInspection(sequence: $sequence)';
}

final class EnrollmentCryptoFormatException implements Exception {
  const EnrollmentCryptoFormatException();
}

final class _BinaryReader {
  _BinaryReader(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  var _offset = 0;

  int get remaining => _bytes.length - _offset;

  Uint8List take(int length) {
    if (length < 0 || _offset + length > _bytes.length) {
      throw const EnrollmentCryptoFormatException();
    }
    final value = Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return value;
  }

  int u8() => take(1).first;

  int u16() => ByteData.sublistView(take(2)).getUint16(0);

  int u32() => ByteData.sublistView(take(4)).getUint32(0);
}

Uint8List _copyExact(Uint8List value, int length) {
  if (value.length != length) {
    throw const EnrollmentCryptoFormatException();
  }
  return Uint8List.fromList(value);
}

bool _same(Uint8List actual, List<int> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < actual.length; index += 1) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}

const enrollmentDeviceLogBucketBytes = _deviceLogBytes;
