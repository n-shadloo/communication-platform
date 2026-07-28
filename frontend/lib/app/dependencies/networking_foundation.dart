import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/features/networking/application/ports/realtime_gateway.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/dio_token_endpoints.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/token_coordinator.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/dio_websocket_gateway.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/platform_socket_connector.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:dio/dio.dart';

/// Scope-owned composition for the single reviewed REST client and socket gateway.
final class NetworkingFoundation {
  const NetworkingFoundation._({
    required this.restClient,
    required this.tokenCoordinator,
    required this.webSocketGateway,
  });

  factory NetworkingFoundation.create({
    required Uri serverOrigin,
    required SessionTokenStore tokenStore,
    required SessionTerminationHandler terminationHandler,
    required TimeSource timeSource,
    required RealtimeReconnectHook reconnectHook,
    Dio? dio,
    SocketConnector? socketConnector,
    NetworkDiagnostics diagnostics = const NoopNetworkDiagnostics(),
    RetryScheduler retryScheduler = const TimerRetryScheduler(),
  }) {
    final restClient = DioRestClient(
      serverOrigin: serverOrigin,
      dio: dio,
      diagnostics: diagnostics,
      retryScheduler: retryScheduler,
    );
    final tokenCoordinator = TokenCoordinator(
      store: tokenStore,
      refreshExchange: DioRefreshTokenExchange(restClient),
      logoutExchange: DioLogoutTokenExchange(restClient),
      terminationHandler: terminationHandler,
      timeSource: timeSource,
    );
    restClient.bindTokenCoordinator(tokenCoordinator);
    final webSocketGateway = DioWebSocketGateway(
      serverOrigin: serverOrigin,
      connector: socketConnector ?? const PlatformSocketConnector(),
      tokenCoordinator: tokenCoordinator,
      reconnectHook: reconnectHook,
      diagnostics: diagnostics,
    );
    return NetworkingFoundation._(
      restClient: restClient,
      tokenCoordinator: tokenCoordinator,
      webSocketGateway: webSocketGateway,
    );
  }

  final DioRestClient restClient;
  final TokenCoordinator tokenCoordinator;
  final DioWebSocketGateway webSocketGateway;
}
