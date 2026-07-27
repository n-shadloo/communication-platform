import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';

final class DioRefreshTokenExchange implements RefreshTokenExchange {
  const DioRefreshTokenExchange(this.client);

  final DioRestClient client;

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async {
    final result = await client.send<TokenPairResponseDto>(
      ApiRequest<TokenPairResponseDto>(
        method: RestMethod.post,
        path: '/api/v1/auth/refresh',
        decode: TokenPairResponseDto.fromJson,
        acceptedStatusCodes: const {200},
        authentication: AuthenticationRequirement.none,
        limits: ApiContractLimits.smallJson,
        operation: NetworkOperation.authRefresh,
        body: RefreshRequestDto(refreshToken).toJson(),
      ),
    );
    return result.fold(
      onSuccess: (dto) => Result.success(dto.toDomain()),
      onFailure: Result.failure,
    );
  }
}

final class DioLogoutTokenExchange implements LogoutTokenExchange {
  const DioLogoutTokenExchange(this.client);

  final DioRestClient client;

  @override
  Future<void> revoke({
    required String accessToken,
    required String refreshToken,
  }) async {
    await client.send<EmptyResponseDto>(
      ApiRequest<EmptyResponseDto>(
        method: RestMethod.post,
        path: '/api/v1/auth/logout',
        decode: EmptyResponseDto.fromJson,
        acceptedStatusCodes: const {205},
        authentication: AuthenticationRequirement.full,
        limits: ApiContractLimits.smallJson,
        operation: NetworkOperation.authLogout,
        body: RefreshRequestDto(refreshToken).toJson(),
      ),
    );
  }
}
