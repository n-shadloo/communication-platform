import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/prekey_maintenance_ports.dart';
import 'package:communication_platform/features/devices/domain/prekey_maintenance_model.dart';
import 'package:communication_platform/features/devices/infrastructure/prekey_api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';

final class DioDevicePrekeyRepository implements DevicePrekeyRemotePort {
  const DioDevicePrekeyRepository(this.client);

  final DioRestClient client;

  @override
  Future<Result<PrekeyCounts>> fetchCounts({required String deviceId}) => client
      .send(
        ApiRequest<PrekeyCountsResponseDto>(
          method: RestMethod.get,
          path: '/api/v1/me/devices/$deviceId/prekeys/count',
          decode: PrekeyCountsResponseDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.prekeyJson,
          replaySafety: ReplaySafety.readOnly,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.counts),
          onFailure: Result.failure,
        ),
      );

  @override
  Future<Result<int>> upload({
    required String deviceId,
    required PrekeyUploadProjection upload,
  }) => client
      .send(
        ApiRequest<PrekeyUploadResponseDto>(
          method: RestMethod.put,
          path: '/api/v1/me/devices/$deviceId/prekeys',
          body: PrekeyUploadRequestDto(upload).toJson(),
          decode: PrekeyUploadResponseDto.fromJson,
          acceptedStatusCodes: const {200},
          authentication: AuthenticationRequirement.full,
          limits: ApiContractLimits.prekeyJson,
          replaySafety: ReplaySafety.contractIdempotent,
        ),
      )
      .then(
        (result) => result.fold(
          onSuccess: (response) => Result.success(response.classicalCount),
          onFailure: Result.failure,
        ),
      );
}
