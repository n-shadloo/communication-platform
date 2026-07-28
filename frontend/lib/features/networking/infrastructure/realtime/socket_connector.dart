enum SocketAuthenticationMode { nativeBearerHeader, webFirstFrame }

abstract interface class SocketConnection {
  Stream<Object?> get messages;

  int? get closeCode;

  void add(Object message);

  Future<void> close([int? code]);
}

abstract interface class SocketConnector {
  SocketAuthenticationMode get authenticationMode;

  Future<SocketConnection> connect({
    required Uri uri,
    required String accessToken,
    required Duration timeout,
  });
}
