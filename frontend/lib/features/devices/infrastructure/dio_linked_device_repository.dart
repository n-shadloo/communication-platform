import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/linked_device_ports.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:communication_platform/features/devices/infrastructure/linked_device_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';

final class DioLinkedDeviceRepository implements LinkedDeviceRemotePort {
  const DioLinkedDeviceRepository(this.client);

  final DioRestClient client;

  @override
  Future<Result<OwnDeviceRefresh>> fetchOwnDevices({String? etag}) => client
      .send(
        ApiRequest<OwnDeviceListResponseDto>(
          method: RestMethod.get,
          path: '/api/v1/me/devices',
          headers: {'If-None-Match': ?etag},
          decode: (json) =>
              OwnDeviceListResponseDto.fromResponse(json, const {}),
          decodeWithHeaders: OwnDeviceListResponseDto.fromResponse,
          acceptedStatusCodes: const {200, 304},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.smallJson,
          replaySafety: ReplaySafety.readOnly,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (dto) => Result.success(dto.refresh),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<void>> relabelDevice({
    required String deviceId,
    required Uint8List encryptedLabel,
  }) => client
      .send(
        ApiRequest<EmptyResponseDto>(
          method: RestMethod.put,
          path: '/api/v1/me/devices/$deviceId',
          body: {'label_blob': base64Encode(encryptedLabel)},
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
