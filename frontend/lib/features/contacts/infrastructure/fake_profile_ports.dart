import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';

/// Development-only profile protection used until pairwise transport exists.
///
/// This adapter deliberately advertises [isProductionReady] as false. Its XOR
/// envelope and 32-bit substitution check are test scaffolding, not cryptography,
/// and the production composition must remain fail-closed.
final class DevelopmentFakeProfileProtection implements ProfileProtectionPort {
  DevelopmentFakeProfileProtection({Random? random})
    : _random = random ?? Random.secure();

  static const _magic = <int>[70, 65, 75, 69, 80, 82, 48, 49];
  final Random _random;

  @override
  bool get isProductionReady => false;

  @override
  Future<Result<(ProfileCiphertext, ProfileKeyMaterial)>> seal({
    required ProfileDraft profile,
    required String authorUserId,
    required String authorDeviceId,
    required int revision,
  }) async {
    if (!profile.isValid || revision <= 0) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 1,
          'display_name': profile.displayName.trim(),
          'avatar_seed': profile.avatarSeed,
          'author_user_id': authorUserId,
          'author_device_id': authorDeviceId,
          'revision': revision,
        }),
      ),
    );
    if (payload.length > 900) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.limitExceeded),
      );
    }
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256), growable: false),
    );
    final encrypted = Uint8List.fromList([
      for (var index = 0; index < payload.length; index += 1)
        payload[index] ^ key[index % key.length],
    ]);
    final blob = Uint8List(1024);
    blob
      ..setRange(0, 8, _magic)
      ..buffer.asByteData().setUint32(8, revision)
      ..buffer.asByteData().setUint16(12, encrypted.length)
      ..setRange(14, 14 + encrypted.length, encrypted);
    blob.buffer.asByteData().setUint32(
      14 + encrypted.length,
      _tag(key, encrypted),
    );
    for (var index = 18 + encrypted.length; index < blob.length; index += 1) {
      blob[index] = _random.nextInt(256);
    }
    return Result.success((
      ProfileCiphertext(blob: blob, version: revision),
      ProfileKeyMaterial(key),
    ));
  }

  @override
  Future<Result<OpenedProfile>> open({
    required ProfileCiphertext ciphertext,
    required ProfileKeyMaterial key,
  }) async {
    try {
      final blob = ciphertext.blob;
      if (blob.length != 1024 ||
          key.bytes.length != 32 ||
          !_same(blob.sublist(0, 8), _magic)) {
        throw const FormatException();
      }
      final data = blob.buffer.asByteData();
      final revision = data.getUint32(8);
      final length = data.getUint16(12);
      if (revision != ciphertext.version ||
          length <= 0 ||
          18 + length > blob.length) {
        throw const FormatException();
      }
      final encrypted = Uint8List.fromList(blob.sublist(14, 14 + length));
      if (data.getUint32(14 + length) != _tag(key.bytes, encrypted)) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        );
      }
      final plaintext = Uint8List.fromList([
        for (var index = 0; index < encrypted.length; index += 1)
          encrypted[index] ^ key.bytes[index % key.bytes.length],
      ]);
      final json = jsonDecode(utf8.decode(plaintext));
      if (json is! Map<String, Object?> ||
          json['format'] != 1 ||
          json['revision'] != revision ||
          json['display_name'] is! String ||
          json['avatar_seed'] is! int ||
          json['author_user_id'] is! String ||
          json['author_device_id'] is! String) {
        throw const FormatException();
      }
      final draft = ProfileDraft(
        displayName: json['display_name']! as String,
        avatarSeed: json['avatar_seed']! as int,
      );
      if (!draft.isValid) {
        throw const FormatException();
      }
      return Result.success(
        OpenedProfile(
          draft: draft,
          authorUserId: json['author_user_id']! as String,
          authorDeviceId: json['author_device_id']! as String,
          revision: revision,
        ),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
  }

  int _tag(Uint8List key, Uint8List value) {
    var hash = 0x811c9dc5;
    for (final byte in <int>[...key, ...value]) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash;
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
}

/// Development-only stand-in for authenticated pairwise profile-key events.
final class DevelopmentFakeProfileKeyDistribution
    implements ProfileKeyDistributionPort {
  final Map<String, ProfileKeyMaterial> _keys = {};

  @override
  bool get isProductionReady => false;

  @override
  Future<Result<void>> publish({
    required String ownerUserId,
    required int profileVersion,
    required ProfileKeyMaterial key,
  }) async {
    _keys['$ownerUserId:$profileVersion'] = ProfileKeyMaterial(key.bytes);
    return const Result.success(null);
  }

  @override
  Future<Result<ProfileKeyMaterial?>> receive({
    required String ownerUserId,
    required int profileVersion,
  }) async => Result.success(_keys['$ownerUserId:$profileVersion']);

  void seed({
    required String ownerUserId,
    required int profileVersion,
    required ProfileKeyMaterial key,
  }) {
    _keys['$ownerUserId:$profileVersion'] = ProfileKeyMaterial(key.bytes);
  }
}

final class UnsupportedProfileProtection implements ProfileProtectionPort {
  const UnsupportedProfileProtection();

  @override
  bool get isProductionReady => false;

  @override
  Future<Result<OpenedProfile>> open({
    required ProfileCiphertext ciphertext,
    required ProfileKeyMaterial key,
  }) => _blocked();

  @override
  Future<Result<(ProfileCiphertext, ProfileKeyMaterial)>> seal({
    required ProfileDraft profile,
    required String authorUserId,
    required String authorDeviceId,
    required int revision,
  }) => _blocked();

  Future<Result<T>> _blocked<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );
}

final class UnsupportedProfileKeyDistribution
    implements ProfileKeyDistributionPort {
  const UnsupportedProfileKeyDistribution();

  @override
  bool get isProductionReady => false;

  @override
  Future<Result<void>> publish({
    required String ownerUserId,
    required int profileVersion,
    required ProfileKeyMaterial key,
  }) => _blocked();

  @override
  Future<Result<ProfileKeyMaterial?>> receive({
    required String ownerUserId,
    required int profileVersion,
  }) => _blocked();

  Future<Result<T>> _blocked<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );
}
