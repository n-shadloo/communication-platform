import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:web_socket_channel/html.dart';

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
    // Ignored: a browser WebSocket has no ping API, and the browser performs
    // its own keepalive. Accepting and discarding it is the honest shape,
    // because pretending to honour it would be worse.
    Duration? keepAlive,
  }) async {
    if (uri.scheme != 'wss' || uri.userInfo.isNotEmpty || uri.hasQuery) {
      throw StateError('Unsafe browser WebSocket origin.');
    }
    // Browser APIs set Origin themselves and forbid custom Authorization headers.
    final channel = HtmlWebSocketChannel.connect(uri);
    await channel.ready.timeout(timeout);
    return _ChannelSocketConnection(channel);
  }
}

final class _ChannelSocketConnection implements SocketConnection {
  const _ChannelSocketConnection(this.channel);

  final HtmlWebSocketChannel channel;

  @override
  int? get closeCode => channel.closeCode;

  @override
  Stream<Object?> get messages => channel.stream;

  @override
  void add(Object message) => channel.sink.add(message);

  @override
  Future<void> close([int? code]) => channel.sink.close(code);
}
