import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';

final class PlatformSocketConnector implements SocketConnector {
  const PlatformSocketConnector();

  @override
  SocketAuthenticationMode get authenticationMode =>
      SocketAuthenticationMode.webFirstFrame;

  @override
  Future<SocketConnection> connect({
    required Uri uri,
    required String accessToken,
    required Duration timeout,
  }) => throw UnsupportedError('WebSockets are unsupported on this platform.');
}
