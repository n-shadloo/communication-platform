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
///
/// Measured, and kept (ADR-060). The cost is one REST round trip per inbound
/// message — 107 to 137 ms from a real phone, connect through close — and one
/// re-download of bytes the socket already carried. What it buys is that a
/// single code path decides what is in this device's mailbox: the drain page is
/// where `pruned_through` arrives, and `pruned_through` against the local
/// contiguous-acknowledgement watermark is the *only* way a lost envelope is
/// detected. A pushed frame carries no such watermark, so seeding the inbox
/// from one would mean a second admission path that cannot answer the question
/// the first exists to answer. The idle re-download that made this look
/// expensive was never this: it was an inbox that could not retire what it
/// could not open, so the same hundred envelopes were served, stored and served
/// again on every cycle.
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
