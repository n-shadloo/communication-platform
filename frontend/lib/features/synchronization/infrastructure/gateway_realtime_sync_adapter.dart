import 'dart:async';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/realtime_gateway.dart';
import 'package:communication_platform/features/networking/domain/realtime_event.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

/// Converts socket delivery into wake-up hints only.
///
/// The envelope bytes carried by a socket event are deliberately ignored. Every hint
/// is followed by an authoritative REST drain through [DurableSyncEngine].
final class GatewayRealtimeSyncAdapter
    implements RealtimeSyncPort, RealtimeReconnectHook {
  final StreamController<void> _hints = StreamController<void>.broadcast();
  final StreamController<RealtimeDisconnect> _disconnects =
      StreamController<RealtimeDisconnect>.broadcast();

  RealtimeGateway? _gateway;
  StreamSubscription<RealtimeEvent>? _subscription;
  bool _disposed = false;

  void attach(RealtimeGateway gateway) {
    if (_disposed || _gateway != null) {
      throw StateError('Realtime gateway can only be attached once.');
    }
    _gateway = gateway;
    _subscription = gateway.events.listen((event) {
      if (event is RealtimeEnvelope) {
        _hints.add(null);
      }
    });
  }

  @override
  Stream<void> get durableEnvelopeHints => _hints.stream;

  @override
  Stream<RealtimeDisconnect> get disconnects => _disconnects.stream;

  @override
  Future<Result<void>> connect() {
    final gateway = _gateway;
    if (gateway == null) {
      return Future.value(
        const Result.failure(
          TransportFailure(TransportFailureKind.connectionRejected),
        ),
      );
    }
    return gateway.connect();
  }

  @override
  void markStableConnection() => _gateway?.markStableConnection();

  @override
  Future<void> close() async {
    await _gateway?.close();
  }

  @override
  Future<void> onDisconnected({
    required RealtimeCloseReason reason,
    required ReconnectAction action,
  }) async {
    if (_disposed) {
      return;
    }
    _disconnects.add(
      RealtimeDisconnect(
        kind: switch (reason) {
          RealtimeCloseReason.authenticationFailed =>
            RealtimeDisconnectKind.authenticationFailed,
          RealtimeCloseReason.revoked => RealtimeDisconnectKind.revoked,
          RealtimeCloseReason.protocolViolation =>
            RealtimeDisconnectKind.protocolViolation,
          RealtimeCloseReason.originRejected =>
            RealtimeDisconnectKind.originRejected,
          RealtimeCloseReason.normal => RealtimeDisconnectKind.normal,
          RealtimeCloseReason.transportLost =>
            RealtimeDisconnectKind.transportLost,
        },
        action: switch (action) {
          ReconnectAction.refreshThenReconnectOnce =>
            RealtimeRecoveryAction.refreshThenReconnectOnce,
          ReconnectAction.reconnectWithBackoff =>
            RealtimeRecoveryAction.reconnectWithBackoff,
          ReconnectAction.stopRevoked => RealtimeRecoveryAction.stopRevoked,
          ReconnectAction.openCircuit => RealtimeRecoveryAction.openCircuit,
          ReconnectAction.stopOriginRejected =>
            RealtimeRecoveryAction.stopOriginRejected,
          ReconnectAction.none => RealtimeRecoveryAction.none,
        },
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await close();
    await _subscription?.cancel();
    _subscription = null;
    await _hints.close();
    await _disconnects.close();
  }
}
