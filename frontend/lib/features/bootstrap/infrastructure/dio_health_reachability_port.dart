// ignore_for_file: prefer_initializing_formals

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';

/// The bootstrap health adapter uses only the configured origin and the typed client.
final class DioHealthReachabilityPort implements HealthReachabilityPort {
  DioHealthReachabilityPort({
    NetworkDiagnostics diagnostics = const NoopNetworkDiagnostics(),
  }) : _diagnostics = diagnostics;

  final NetworkDiagnostics _diagnostics;
  DioRestClient? _client;
  Uri? _origin;

  @override
  Future<HealthReachabilityResult> check(
    ProvisionedBootstrapConfiguration configuration,
  ) async {
    final origin = configuration.serverOrigin.uri;
    if (_client == null || _origin != origin) {
      _origin = origin;
      _client = DioRestClient(serverOrigin: origin, diagnostics: _diagnostics);
    }
    final result = await _client!.send<HealthResponseDto>(
      ApiRequest<HealthResponseDto>(
        method: RestMethod.get,
        path: '/api/v1/health',
        decode: HealthResponseDto.fromJson,
        acceptedStatusCodes: const {200},
        authentication: AuthenticationRequirement.none,
        limits: ApiContractLimits.smallJson,
        operation: NetworkOperation.health,
        replaySafety: ReplaySafety.readOnly,
      ),
    );
    return result is Success<HealthResponseDto>
        ? const HealthReachable()
        : const HealthUnreachable();
  }
}
