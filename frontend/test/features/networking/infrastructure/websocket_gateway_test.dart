import 'dart:async';
import 'dart:convert';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/realtime_gateway.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/realtime_event.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/dio_websocket_gateway.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'web connect uses wss and sends access only in the first auth frame',
    () async {
      final connection = FakeSocketConnection();
      final connector = FakeSocketConnector(
        authenticationMode: SocketAuthenticationMode.webFirstFrame,
        connection: connection,
      );
      final gateway = gatewayFor(connector: connector);

      final result = await gateway.connect();
      expect(result, isA<Success<void>>());
      expect(connector.uri, Uri.parse('wss://chat.example.test/ws'));
      expect(connector.uri!.hasQuery, isFalse);
      expect(connector.accessToken, 'socket-access');
      expect(jsonDecode(connection.sent.single as String), {
        'type': 'auth',
        'access': 'socket-access',
      });
      await gateway.close();
    },
  );

  test('native connect sends no in-band auth frame', () async {
    final connection = FakeSocketConnection();
    final connector = FakeSocketConnector(
      authenticationMode: SocketAuthenticationMode.nativeBearerHeader,
      connection: connection,
    );
    final gateway = gatewayFor(connector: connector);

    await gateway.connect();
    expect(connection.sent, isEmpty);
    expect(connector.accessToken, 'socket-access');
    await gateway.close();
  });

  test('decodes transport events without retaining business state', () async {
    final connection = FakeSocketConnection();
    final gateway = gatewayFor(
      connector: FakeSocketConnector(
        authenticationMode: SocketAuthenticationMode.webFirstFrame,
        connection: connection,
      ),
    );
    await gateway.connect();
    final eventFuture = gateway.events.first;
    connection.serverMessage(
      jsonEncode({
        'type': 'envelope',
        'id': 'e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b',
        'seq': 12,
        'blob': envelopeBlob(),
      }),
    );

    final event = await eventFuture;
    expect(event, isA<RealtimeEnvelope>());
    expect((event as RealtimeEnvelope).sequence, 12);
    await gateway.close();
  });

  test('malformed or binary server frame opens the protocol circuit', () async {
    final connection = FakeSocketConnection();
    final hook = RecordingReconnectHook();
    final gateway = gatewayFor(
      connector: FakeSocketConnector(
        authenticationMode: SocketAuthenticationMode.webFirstFrame,
        connection: connection,
      ),
      hook: hook,
    );
    await gateway.connect();
    connection.serverMessage(<int>[1, 2, 3]);
    await pumpEvents();

    expect(connection.closeCode, 4008);
    expect(hook.records.single, (
      RealtimeCloseReason.protocolViolation,
      ReconnectAction.openCircuit,
    ));
  });

  test('maps every backend close code to its reconnect hook', () async {
    const cases = <(int, RealtimeCloseReason, ReconnectAction)>[
      (
        4001,
        RealtimeCloseReason.authenticationFailed,
        ReconnectAction.refreshThenReconnectOnce,
      ),
      (4003, RealtimeCloseReason.revoked, ReconnectAction.stopRevoked),
      (
        4008,
        RealtimeCloseReason.protocolViolation,
        ReconnectAction.openCircuit,
      ),
      (
        4403,
        RealtimeCloseReason.originRejected,
        ReconnectAction.stopOriginRejected,
      ),
      (1000, RealtimeCloseReason.normal, ReconnectAction.none),
    ];

    for (final entry in cases) {
      final connection = FakeSocketConnection();
      final hook = RecordingReconnectHook();
      final tokens = FakeSocketTokenCoordinator();
      final gateway = gatewayFor(
        connector: FakeSocketConnector(
          authenticationMode: SocketAuthenticationMode.webFirstFrame,
          connection: connection,
        ),
        hook: hook,
        tokenCoordinator: tokens,
      );
      await gateway.connect();
      await connection.serverClose(entry.$1);
      await pumpEvents();

      expect(hook.records.single, (entry.$2, entry.$3));
      expect(tokens.recoveries, entry.$1 == 4001 ? 1 : 0);
      expect(tokens.revocations, entry.$1 == 4003 ? 1 : 0);
    }
  });

  test(
    '4001 authentication recovery is circuit-limited until stable',
    () async {
      final connector = MultiSocketConnector();
      final hook = RecordingReconnectHook();
      final gateway = gatewayFor(connector: connector, hook: hook);

      await gateway.connect();
      await connector.connections[0].serverClose(4001);
      await pumpEvents();
      await gateway.connect();
      await connector.connections[1].serverClose(4001);
      await pumpEvents();
      expect(hook.records[1].$2, ReconnectAction.none);

      await gateway.connect();
      gateway.markStableConnection();
      await connector.connections[2].serverClose(4001);
      await pumpEvents();
      expect(hook.records[2].$2, ReconnectAction.refreshThenReconnectOnce);
    },
  );

  test('rejects non-HTTPS origins and oversized outbound frames', () async {
    expect(
      () => DioWebSocketGateway(
        serverOrigin: Uri.parse('http://chat.example.test'),
        connector: MultiSocketConnector(),
        tokenCoordinator: FakeSocketTokenCoordinator(),
        reconnectHook: RecordingReconnectHook(),
      ),
      throwsArgumentError,
    );

    final connection = FakeSocketConnection();
    final gateway = gatewayFor(
      connector: FakeSocketConnector(
        authenticationMode: SocketAuthenticationMode.webFirstFrame,
        connection: connection,
      ),
    );
    await gateway.connect();
    final result = await gateway.send({
      'type': 'signal',
      'blob': List<String>.filled(524289, 'x').join(),
    });
    expect(result, isA<FailureResult<void>>());
    expect(
      connection.sent.length,
      1,
      reason: 'only the web auth frame is sent',
    );
    await gateway.close();
  });

  test('enforces documented outgoing frame field and count limits', () async {
    final connection = FakeSocketConnection();
    final gateway = gatewayFor(
      connector: FakeSocketConnector(
        authenticationMode: SocketAuthenticationMode.webFirstFrame,
        connection: connection,
      ),
    );
    await gateway.connect();
    const id = 'e4f8a1c2-9b3d-4e5f-8a70-6c1d2e3f4a5b';

    final valid = await gateway.send({
      'type': 'ack',
      'ids': const <Object?>[id],
    });
    expect(valid, isA<Success<void>>());

    final tooManyAcks = await gateway.send({
      'type': 'ack',
      'ids': List<Object?>.filled(201, id),
    });
    final tooManyPresenceTargets = await gateway.send({
      'type': 'subscribe_presence',
      'device_ids': List<Object?>.filled(501, id),
    });
    final extraField = await gateway.send({
      'type': 'signal',
      'to_device': id,
      'blob': 'opaque',
      'plaintext': 'must never be sent',
    });
    expect(tooManyAcks, isA<FailureResult<void>>());
    expect(tooManyPresenceTargets, isA<FailureResult<void>>());
    expect(extraField, isA<FailureResult<void>>());
    expect(connection.sent.length, 2, reason: 'auth plus one valid ack only');
    await gateway.close();
  });
}

DioWebSocketGateway gatewayFor({
  required SocketConnector connector,
  RecordingReconnectHook? hook,
  FakeSocketTokenCoordinator? tokenCoordinator,
}) => DioWebSocketGateway(
  serverOrigin: Uri.parse('https://chat.example.test'),
  connector: connector,
  tokenCoordinator: tokenCoordinator ?? FakeSocketTokenCoordinator(),
  reconnectHook: hook ?? RecordingReconnectHook(),
);

final class FakeSocketConnection implements SocketConnection {
  final StreamController<Object?> controller = StreamController<Object?>();
  final List<Object> sent = [];

  @override
  int? closeCode;

  @override
  Stream<Object?> get messages => controller.stream;

  @override
  void add(Object message) => sent.add(message);

  void serverMessage(Object message) => controller.add(message);

  Future<void> serverClose(int code) async {
    closeCode = code;
    await controller.close();
  }

  @override
  Future<void> close([int? code]) async {
    closeCode = code;
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

final class FakeSocketConnector implements SocketConnector {
  FakeSocketConnector({
    required this.authenticationMode,
    required this.connection,
  });

  @override
  final SocketAuthenticationMode authenticationMode;
  final FakeSocketConnection connection;
  Uri? uri;
  String? accessToken;

  @override
  Future<SocketConnection> connect({
    required Uri uri,
    required String accessToken,
    required Duration timeout,
    Duration? keepAlive,
  }) async {
    this.uri = uri;
    this.accessToken = accessToken;
    return connection;
  }
}

final class MultiSocketConnector implements SocketConnector {
  final List<FakeSocketConnection> connections = [];

  @override
  SocketAuthenticationMode get authenticationMode =>
      SocketAuthenticationMode.webFirstFrame;

  @override
  Future<SocketConnection> connect({
    required Uri uri,
    required String accessToken,
    required Duration timeout,
    Duration? keepAlive,
  }) async {
    final connection = FakeSocketConnection();
    connections.add(connection);
    return connection;
  }
}

final class FakeSocketTokenCoordinator implements AccessTokenCoordinator {
  int recoveries = 0;
  int revocations = 0;

  @override
  Future<Result<AccessToken>> accessToken({bool forceRefresh = false}) async =>
      Result.success(
        AccessToken(
          value: 'socket-access',
          expiresAt: DateTime.utc(2100),
          scope: SessionScope.full,
        ),
      );

  @override
  Future<Result<AccessToken>> recoverAfterUnauthorized(String rejectedToken) {
    recoveries += 1;
    return accessToken();
  }

  @override
  Future<void> handleRevocation() {
    revocations += 1;
    return Future<void>.value();
  }

  @override
  Future<void> logout() async {}
}

final class RecordingReconnectHook implements RealtimeReconnectHook {
  final List<(RealtimeCloseReason, ReconnectAction)> records = [];

  @override
  Future<void> onDisconnected({
    required RealtimeCloseReason reason,
    required ReconnectAction action,
  }) async {
    records.add((reason, action));
  }
}

Future<void> pumpEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

String envelopeBlob() => base64.encode(List<int>.filled(1024, 0));
