import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/device_enrollment_ports.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';
import 'package:communication_platform/features/devices/infrastructure/device_enrollment_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';

final class DioDeviceEnrollmentRepository
    implements DeviceEnrollmentRepository {
  const DioDeviceEnrollmentRepository(this.client);

  final DioRestClient client;

  @override
  Future<Result<DeviceRegistrationResponse>> registerDevice({
    required String userId,
    required DeviceRegistrationPublic public,
  }) => client
      .send(
        ApiRequest<RegisterDeviceResponseDto>(
          method: RestMethod.post,
          path: '/api/v1/me/devices',
          body: RegisterDeviceRequestDto(public).toJson(),
          decode: RegisterDeviceResponseDto.fromJson,
          acceptedStatusCodes: const {201},
          authentication: AuthenticationRequirement.registerOrFull,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.never,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.toDomain(userId)),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<void>> publishIdentity({required PublishedIdentity identity}) =>
      client
          .send(
            ApiRequest<EmptyResponseDto>(
              method: RestMethod.put,
              path: '/api/v1/me/identity',
              body: IdentityRequestDto(identity).toJson(),
              decode: EmptyResponseDto.fromJson,
              acceptedStatusCodes: const {200},
              authentication: AuthenticationRequirement.full,
              limits: ApiContractLimits.smallJson,
              replaySafety: ReplaySafety.contractIdempotent,
            ),
          )
          .then(
            (result) => result.fold(
              onSuccess: (_) => const Result.success(null),
              onFailure: Result.failure,
            ),
          );

  @override
  Future<Result<PublishedIdentity>> fetchIdentity({required String userId}) =>
      client
          .send(
            ApiRequest<IdentityResponseDto>(
              method: RestMethod.get,
              path: '/api/v1/users/$userId/identity',
              decode: IdentityResponseDto.fromJson,
              acceptedStatusCodes: const {200},
              authentication: AuthenticationRequirement.full,
              limits: ApiContractLimits.smallJson,
              replaySafety: ReplaySafety.readOnly,
            ),
          )
          .then(
            (result) => result.fold(
              onSuccess: (response) => Result.success(response.toDomain()),
              onFailure: Result.failure,
            ),
          );

  @override
  Future<Result<void>> finishPrekeys({
    required String deviceId,
    required Uint8List crossSignature,
    required int bundleVersion,
  }) => client
      .send(
        ApiRequest<EmptyResponseDto>(
          method: RestMethod.put,
          path: '/api/v1/me/devices/$deviceId/prekeys',
          body: PrekeyFollowUpRequestDto(
            crossSignature: crossSignature,
            bundleVersion: bundleVersion,
          ).toJson(),
          decode: (json) {
            final object = requireJsonObject(json);
            if (object['otpk_count'] is! int ||
                (object['otpk_count'] as int) < 0) {
              throw const MalformedApiBody();
            }
            return const EmptyResponseDto();
          },
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.contractIdempotent,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (_) => const Result.success(null),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<KeyBackup>> fetchBackup() => client
      .send(
        ApiRequest<BackupResponseDto>(
          method: RestMethod.get,
          path: '/api/v1/me/keybackup',
          decode: BackupResponseDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.backupJson,
          replaySafety: ReplaySafety.readOnly,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.toDomain()),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<void>> uploadBackup({
    required Uint8List blob,
    required int version,
  }) => client
      .send(
        ApiRequest<EmptyResponseDto>(
          method: RestMethod.put,
          path: '/api/v1/me/keybackup',
          body: BackupRequestDto(blob: blob, version: version).toJson(),
          decode: EmptyResponseDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.backupJson,
          replaySafety: ReplaySafety.never,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (_) => const Result.success(null),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<PublicDeviceList>> fetchPublicDevices({
    required String userId,
  }) => client
      .send(
        ApiRequest<PublicDevicesResponseDto>(
          method: RestMethod.get,
          path: '/api/v1/users/$userId/devices',
          decode: PublicDevicesResponseDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.readOnly,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.toDomain()),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<DeviceLogPage>> fetchDeviceLog({
    required String userId,
    int? after,
  }) => client
      .send(
        ApiRequest<DeviceLogPageDto>(
          method: RestMethod.get,
          path: '/api/v1/users/$userId/devicelog',
          queryParameters: {'after': ?after},
          decode: DeviceLogPageDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.readOnly,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.toDomain()),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<DeviceLogAppendResult>> appendDeviceLog({
    required Uint8List record,
  }) => client
      .send(
        ApiRequest<DeviceLogAppendResponseDto>(
          method: RestMethod.post,
          path: '/api/v1/me/devicelog',
          body: {
            'records': [
              {'blob': base64Encode(record)},
            ],
          },
          decode: DeviceLogAppendResponseDto.fromJson,
          acceptedStatusCodes: const {201},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.never,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.toDomain()),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<void>> revokeDevice({required String deviceId}) => client
      .send(
        ApiRequest<EmptyResponseDto>(
          method: RestMethod.delete,
          path: '/api/v1/me/devices/$deviceId',
          decode: EmptyResponseDto.fromJson,
          acceptedStatusCodes: const {204},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.never,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (_) => const Result.success(null),
          onFailure: Result.failure,
        ),
      );
}
