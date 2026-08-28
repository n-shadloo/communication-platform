import 'dart:convert';

import 'package:communication_platform/features/devices/domain/prekey_maintenance_model.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';

final class PrekeyCountsResponseDto {
  const PrekeyCountsResponseDto(this.counts);

  factory PrekeyCountsResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    if (json.length != 2 ||
        !json.containsKey('otpk_count') ||
        !json.containsKey('pq_otpk_count')) {
      throw const MalformedApiBody();
    }
    return PrekeyCountsResponseDto(
      PrekeyCounts(
        classical: _count(json['otpk_count'], 200),
        postQuantum: _count(json['pq_otpk_count'], 100),
      ),
    );
  }

  final PrekeyCounts counts;
}

final class PrekeyUploadResponseDto {
  const PrekeyUploadResponseDto(this.classicalCount);

  factory PrekeyUploadResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    if (json.length != 1 || !json.containsKey('otpk_count')) {
      throw const MalformedApiBody();
    }
    return PrekeyUploadResponseDto(_count(json['otpk_count'], 200));
  }

  final int classicalCount;
}

final class PrekeyUploadRequestDto {
  const PrekeyUploadRequestDto(this.projection);

  final PrekeyUploadProjection projection;

  Map<String, Object?> toJson() {
    final rotation = projection.rotation;
    return <String, Object?>{
      if (rotation != null)
        'spk': {
          'spk_id': rotation.classical.keyId,
          'pub': base64Encode(rotation.classical.publicKey),
          'sig': base64Encode(rotation.classical.signature),
        },
      if (rotation != null) 'cross_sig': base64Encode(rotation.crossSignature),
      if (rotation != null) 'bundle_version': rotation.bundleVersion,
      if (rotation != null)
        'pq_spk': {
          'spk_id': rotation.postQuantum.keyId,
          'pub': base64Encode(rotation.postQuantum.publicKey),
          'sig': base64Encode(rotation.postQuantum.signature),
        },
      if (projection.pqOneTimePrekeys.isNotEmpty)
        'pq_otpks': [
          for (final prekey in projection.pqOneTimePrekeys)
            {'key_id': prekey.keyId, 'pub': base64Encode(prekey.publicKey)},
        ],
      if (projection.classicalOneTimePrekeys.isNotEmpty)
        'otpks': [
          for (final prekey in projection.classicalOneTimePrekeys)
            {'key_id': prekey.keyId, 'pub': base64Encode(prekey.publicKey)},
        ],
    };
  }
}

int _count(Object? value, int maximum) {
  if (value is! int || value < 0 || value > maximum) {
    throw const MalformedApiBody();
  }
  return value;
}
