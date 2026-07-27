import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:web_socket_channel/io.dart';

final class PlatformSocketConnector implements SocketConnector {
  const PlatformSocketConnector();

  @override
  SocketAuthenticationMode get authenticationMode =>
      SocketAuthenticationMode.nativeBearerHeader;

  @override
  Future<SocketConnection> connect({
    required Uri uri,
    required String accessToken,
    required Duration timeout,
  }) async {
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
      connectTimeout: timeout,
    );
    await channel.ready;
    return _ChannelSocketConnection(channel);
  }
}

final class _ChannelSocketConnection implements SocketConnection {
  const _ChannelSocketConnection(this.channel);

  final IOWebSocketChannel channel;

  @override
  int? get closeCode => channel.closeCode;

  @override
  Stream<Object?> get messages => channel.stream;

  @override
  void add(Object message) => channel.sink.add(message);

  @override
  Future<void> close([int? code]) => channel.sink.close(code);
}
