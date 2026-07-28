import 'dart:convert';
import 'dart:typed_data';

final class PeerIdentityPublic {
  PeerIdentityPublic({
    required Uint8List masterPublic,
    required Uint8List selfSigningPublic,
    required Uint8List userSigningPublic,
    required Uint8List masterSignature,
    required this.version,
  }) : masterPublic = _exact(masterPublic, 32),
       selfSigningPublic = _exact(selfSigningPublic, 32),
       userSigningPublic = _exact(userSigningPublic, 32),
       masterSignature = _exact(masterSignature, 64) {
    if (version <= 0) {
      throw const IdentityProtocolFormatException();
    }
  }

  final Uint8List masterPublic;
  final Uint8List selfSigningPublic;
  final Uint8List userSigningPublic;
  final Uint8List masterSignature;
  final int version;
}

final class ClaimedPrekeyBundle {
  ClaimedPrekeyBundle({
    required this.deviceId,
    required this.registrationId,
    required Uint8List identityPublic,
    required this.signedPrekeyId,
    required Uint8List signedPrekeyPublic,
    required Uint8List signedPrekeySignature,
    required Uint8List crossSignature,
    required this.bundleVersion,
    this.pqSignedPrekeyId,
    Uint8List? pqSignedPrekeyPublic,
    Uint8List? pqSignedPrekeySignature,
    this.oneTimePrekeyId,
    Uint8List? oneTimePrekeyPublic,
    this.pqOneTimePrekeyId,
    Uint8List? pqOneTimePrekeyPublic,
  }) : identityPublic = _exact(identityPublic, 64),
       signedPrekeyPublic = _copy(signedPrekeyPublic),
       signedPrekeySignature = _exact(signedPrekeySignature, 64),
       crossSignature = _exact(crossSignature, 64),
       pqSignedPrekeyPublic = _copyNullable(pqSignedPrekeyPublic),
       pqSignedPrekeySignature = pqSignedPrekeySignature == null
           ? null
           : _exact(pqSignedPrekeySignature, 64),
       oneTimePrekeyPublic = _copyNullable(oneTimePrekeyPublic),
       pqOneTimePrekeyPublic = _copyNullable(pqOneTimePrekeyPublic) {
    final pqFields = <Object?>[
      pqSignedPrekeyId,
      this.pqSignedPrekeyPublic,
      this.pqSignedPrekeySignature,
    ];
    if (bundleVersion <= 0 ||
        signedPrekeyPublic.isEmpty ||
        (pqFields.any((value) => value != null) &&
            pqFields.any((value) => value == null))) {
      throw const IdentityProtocolFormatException();
    }
  }

  final String deviceId;
  final int registrationId;
  final Uint8List identityPublic;
  final int signedPrekeyId;
  final Uint8List signedPrekeyPublic;
  final Uint8List signedPrekeySignature;
  final Uint8List crossSignature;
  final int bundleVersion;
  final int? pqSignedPrekeyId;
  final Uint8List? pqSignedPrekeyPublic;
  final Uint8List? pqSignedPrekeySignature;
  final int? oneTimePrekeyId;
  final Uint8List? oneTimePrekeyPublic;
  final int? pqOneTimePrekeyId;
  final Uint8List? pqOneTimePrekeyPublic;

  bool get hasPostQuantumSignedPrekey => pqSignedPrekeyId != null;
}

final class PeerPublicDevice {
  PeerPublicDevice({
    required this.deviceId,
    required Uint8List identityPublic,
    required this.registrationId,
    required this.bundleVersion,
    Uint8List? crossSignature,
  }) : identityPublic = _exact(identityPublic, 64),
       crossSignature = crossSignature == null
           ? null
           : _exact(crossSignature, 64) {
    if ((this.crossSignature == null) != (bundleVersion == null) ||
        (bundleVersion != null && bundleVersion! <= 0)) {
      throw const IdentityProtocolFormatException();
    }
  }

  final String deviceId;
  final Uint8List identityPublic;
  final int registrationId;
  final Uint8List? crossSignature;
  final int? bundleVersion;

  bool get isUnsigned => crossSignature == null;
}

final class PeerDeviceLogInspection {
  PeerDeviceLogInspection({
    required this.sequence,
    required Uint8List previousHash,
    required Uint8List recordHash,
    required Uint8List liveDeviceSetHash,
    required this.identityVersion,
  }) : previousHash = _exact(previousHash, 32),
       recordHash = _exact(recordHash, 32),
       liveDeviceSetHash = _exact(liveDeviceSetHash, 32);

  factory PeerDeviceLogInspection.fromNative(Uint8List bytes) {
    if (bytes.length != 108) {
      throw const IdentityProtocolFormatException();
    }
    final data = ByteData.sublistView(bytes);
    return PeerDeviceLogInspection(
      sequence: data.getUint64(0),
      previousHash: bytes.sublist(8, 40),
      recordHash: bytes.sublist(40, 72),
      liveDeviceSetHash: bytes.sublist(72, 104),
      identityVersion: data.getUint32(104),
    );
  }

  final int sequence;
  final Uint8List previousHash;
  final Uint8List recordHash;
  final Uint8List liveDeviceSetHash;
  final int identityVersion;
}

final class SafetyFingerprint {
  SafetyFingerprint(Uint8List digest) : digest = _exact(digest, 32);

  final Uint8List digest;

  String get qrValue =>
      'CP-SAFETY-V1:${base64Url.encode(digest).replaceAll('=', '')}';

  String get numericCode {
    final groups = <String>[];
    for (var index = 0; index < 10; index += 1) {
      final offset = (index * 3) % digest.length;
      final value =
          (digest[offset] << 16) |
          (digest[(offset + 1) % digest.length] << 8) |
          digest[(offset + 2) % digest.length];
      groups.add((value % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  String get emojiCode => List<String>.generate(
    7,
    (index) => _safetyEmoji[digest[index] % _safetyEmoji.length],
    growable: false,
  ).join(' ');
}

final class UserSigningAttestation {
  UserSigningAttestation(Uint8List signature)
    : signature = _exact(signature, 64);

  final Uint8List signature;
}

final class IdentityProtocolFormatException implements Exception {
  const IdentityProtocolFormatException();
}

const _safetyEmoji = <String>[
  '🐶',
  '🐱',
  '🦁',
  '🐎',
  '🦄',
  '🐷',
  '🐘',
  '🐰',
  '🐼',
  '🐓',
  '🐧',
  '🐢',
  '🐟',
  '🐙',
  '🦋',
  '🌷',
  '🌳',
  '🌵',
  '🍄',
  '🌏',
  '🌙',
  '☁️',
  '🔥',
  '🍌',
  '🍎',
  '🍓',
  '🌽',
  '🍕',
  '🎂',
  '❤️',
  '😀',
  '🤖',
  '🎩',
  '👓',
  '🔧',
  '🎅',
  '👍',
  '☂️',
  '⌛',
  '⏰',
  '🎁',
  '💡',
  '📕',
  '✏️',
  '📎',
  '🔒',
  '🔑',
  '🔨',
  '☎️',
  '🏁',
  '🚂',
  '🚲',
  '✈️',
  '🚀',
  '🏆',
  '⚽',
  '🎸',
  '🎺',
  '🔔',
  '⚓',
  '🎧',
  '📁',
  '📌',
  '🔍',
];

Uint8List _exact(Uint8List value, int length) {
  if (value.length != length) {
    throw const IdentityProtocolFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copy(Uint8List value) => Uint8List.fromList(value);

Uint8List? _copyNullable(Uint8List? value) =>
    value == null ? null : Uint8List.fromList(value);
