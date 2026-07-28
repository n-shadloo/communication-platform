import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';

final class RegisterAccountRequestDto {
  const RegisterAccountRequestDto({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  Map<String, Object?> toJson() => {'username': username, 'password': password};
}

final class RegisterAccountResponseDto {
  const RegisterAccountResponseDto._(this.userId);

  factory RegisterAccountResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final userId = json['user_id'];
    if (userId is! String || !_uuid.hasMatch(userId)) {
      throw const MalformedApiBody();
    }
    return RegisterAccountResponseDto._(userId);
  }

  final String userId;

  AccountRegistration toDomain() => AccountRegistration(userId: userId);
}

final class LoginAccountRequestDto {
  const LoginAccountRequestDto({
    required this.username,
    required this.password,
    this.deviceId,
  });

  final String username;
  final String password;
  final String? deviceId;

  Map<String, Object?> toJson() => {
    'username': username,
    'password': password,
    if (deviceId != null) 'device_id': deviceId,
  };
}

final class LoginAccountResponseDto {
  const LoginAccountResponseDto._({
    required this.access,
    required this.accessExpiresAt,
    required this.userId,
    required this.scope,
    this.refresh,
    this.refreshExpiresAt,
    this.deviceId,
  });

  factory LoginAccountResponseDto.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final access = json['access'];
    final userId = json['user_id'];
    final scope = json['scope'];
    if (access is! String ||
        access.isEmpty ||
        userId is! String ||
        !_uuid.hasMatch(userId) ||
        scope is! String) {
      throw const MalformedApiBody();
    }

    final accessExpiresAt = readJwtExpiry(access);
    switch (scope) {
      case 'register':
        if (json['refresh'] != null || json['device_id'] != null) {
          throw const MalformedApiBody();
        }
        return LoginAccountResponseDto._(
          access: access,
          accessExpiresAt: accessExpiresAt,
          userId: userId,
          scope: AccountSessionScope.register,
        );
      case 'full':
        final refresh = json['refresh'];
        final deviceId = json['device_id'];
        if (refresh is! String ||
            refresh.isEmpty ||
            deviceId is! String ||
            !_uuid.hasMatch(deviceId)) {
          throw const MalformedApiBody();
        }
        return LoginAccountResponseDto._(
          access: access,
          accessExpiresAt: accessExpiresAt,
          refresh: refresh,
          refreshExpiresAt: readJwtExpiry(refresh),
          userId: userId,
          deviceId: deviceId,
          scope: AccountSessionScope.full,
        );
      default:
        throw const MalformedApiBody();
    }
  }

  final String access;
  final DateTime accessExpiresAt;
  final String? refresh;
  final DateTime? refreshExpiresAt;
  final String userId;
  final String? deviceId;
  final AccountSessionScope scope;

  AccountSessionGrant toDomain() => AccountSessionGrant(
    accessToken: access,
    accessExpiresAt: accessExpiresAt,
    refreshToken: refresh,
    refreshExpiresAt: refreshExpiresAt,
    userId: userId,
    deviceId: deviceId,
    scope: scope,
  );
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
