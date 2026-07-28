sealed class RealtimeEvent {
  const RealtimeEvent();
}

final class RealtimeEnvelope extends RealtimeEvent {
  const RealtimeEnvelope({
    required this.id,
    required this.sequence,
    required this.blob,
  });

  final String id;
  final int sequence;
  final String blob;
}

final class RealtimeSignal extends RealtimeEvent {
  const RealtimeSignal(this.blob);

  final String blob;
}

enum PresenceState { online, offline }

final class RealtimePresence extends RealtimeEvent {
  const RealtimePresence({required this.deviceId, required this.state});

  final String deviceId;
  final PresenceState state;
}

final class RealtimeRoomSignal extends RealtimeEvent {
  const RealtimeRoomSignal({required this.roomId, required this.blob});

  final String roomId;
  final String blob;
}

enum RoomPresenceState { join, leave }

final class RealtimeRoomPresence extends RealtimeEvent {
  const RealtimeRoomPresence({
    required this.roomId,
    required this.deviceId,
    required this.state,
  });

  final String roomId;
  final String deviceId;
  final RoomPresenceState state;
}

/// Unknown future event types are retained as unsupported transport events.
final class UnsupportedRealtimeEvent extends RealtimeEvent {
  const UnsupportedRealtimeEvent();
}

enum RealtimeCloseReason {
  authenticationFailed,
  revoked,
  protocolViolation,
  originRejected,
  normal,
  transportLost,
}

enum ReconnectAction {
  refreshThenReconnectOnce,
  reconnectWithBackoff,
  stopRevoked,
  openCircuit,
  stopOriginRejected,
  none,
}
