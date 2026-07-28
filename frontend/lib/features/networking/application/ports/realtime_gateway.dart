import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/domain/realtime_event.dart';

abstract interface class RealtimeReconnectHook implements Port {
  Future<void> onDisconnected({
    required RealtimeCloseReason reason,
    required ReconnectAction action,
  });
}

abstract interface class RealtimeGateway implements Port {
  Stream<RealtimeEvent> get events;

  Future<Result<void>> connect();

  Future<Result<void>> send(Map<String, Object?> frame);

  void markStableConnection();

  Future<void> close();
}
