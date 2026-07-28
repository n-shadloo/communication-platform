import 'dart:convert';

import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';

final class MalformedApiBody implements Exception {
  const MalformedApiBody();
}

Map<String, Object?> requireJsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const MalformedApiBody();
  }
  return value;
}

final class HealthResponseDto {
  const HealthResponseDto();

  factory HealthResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    if (json['status'] != 'ok') {
      throw const MalformedApiBody();
    }
    return const HealthResponseDto();
  }
}

final class RefreshRequestDto {
  const RefreshRequestDto(this.refreshToken);

  final String refreshToken;

  Map<String, Object?> toJson() => {'refresh': refreshToken};
}

final class TokenPairResponseDto {
  const TokenPairResponseDto._({
    required this.access,
    required this.refresh,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  factory TokenPairResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final access = json['access'];
    final refresh = json['refresh'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty) {
      throw const MalformedApiBody();
    }
    return TokenPairResponseDto._(
      access: access,
      refresh: refresh,
      accessExpiresAt: readJwtExpiry(access),
      refreshExpiresAt: readJwtExpiry(refresh),
    );
  }

  final String access;
  final String refresh;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  SessionTokens toDomain() => SessionTokens(
    accessToken: AccessToken(
      value: access,
      expiresAt: accessExpiresAt,
      scope: SessionScope.full,
    ),
    refreshToken: refresh,
    refreshExpiresAt: refreshExpiresAt,
  );
}

final class ErrorEnvelopeDto {
  const ErrorEnvelopeDto({required this.code});

  factory ErrorEnvelopeDto.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      return const ErrorEnvelopeDto(code: null);
    }
    final code = value['code'];
    return ErrorEnvelopeDto(code: code is String ? code : null);
  }

  /// `detail` is intentionally neither parsed nor retained.
  final String? code;
}

final class EmptyResponseDto {
  const EmptyResponseDto();

  factory EmptyResponseDto.fromJson(Object? value) {
    if (value != null) {
      throw const MalformedApiBody();
    }
    return const EmptyResponseDto();
  }
}

final class EnvelopeDto {
  const EnvelopeDto({
    required this.id,
    required this.sequence,
    required this.blob,
  });

  factory EnvelopeDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final id = json['id'];
    final sequence = json['seq'];
    final blob = json['blob'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        sequence is! int ||
        sequence < 1 ||
        blob is! String ||
        !isCanonicalBase64Bucket(blob, ApiContractLimits.envelopeBuckets)) {
      throw const MalformedApiBody();
    }
    return EnvelopeDto(id: id, sequence: sequence, blob: blob);
  }

  final String id;
  final int sequence;
  final String blob;
}

bool isCanonicalBase64Bucket(String value, Set<int> allowedDecodedBytes) {
  if (value.isEmpty ||
      value.length % 4 != 0 ||
      !_standardBase64.hasMatch(value)) {
    return false;
  }
  final padding = value.endsWith('==')
      ? 2
      : value.endsWith('=')
      ? 1
      : 0;
  final decodedBytes = (value.length ~/ 4 * 3) - padding;
  return allowedDecodedBytes.contains(decodedBytes);
}

final class DrainEnvelopesResponseDto {
  const DrainEnvelopesResponseDto({
    required this.envelopes,
    required this.hasMore,
    required this.prunedThrough,
  });

  factory DrainEnvelopesResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final values = json['envelopes'];
    final hasMore = json['has_more'];
    final prunedThrough = json['pruned_through'];
    if (values is! List<Object?> ||
        hasMore is! bool ||
        prunedThrough is! int ||
        prunedThrough < 0 ||
        values.length > 100) {
      throw const MalformedApiBody();
    }
    return DrainEnvelopesResponseDto(
      envelopes: values.map(EnvelopeDto.fromJson).toList(growable: false),
      hasMore: hasMore,
      prunedThrough: prunedThrough,
    );
  }

  final List<EnvelopeDto> envelopes;
  final bool hasMore;
  final int prunedThrough;
}

DateTime readJwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3 || parts[1].length > 16384) {
    throw const MalformedApiBody();
  }
  try {
    final payloadBytes = base64Url.decode(base64Url.normalize(parts[1]));
    final payload = jsonDecode(utf8.decode(payloadBytes));
    final json = requireJsonObject(payload);
    final expiry = json['exp'];
    if (expiry is! int || expiry <= 0) {
      throw const MalformedApiBody();
    }
    return DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
  } on FormatException {
    throw const MalformedApiBody();
  }
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _standardBase64 = RegExp(
  r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
);
