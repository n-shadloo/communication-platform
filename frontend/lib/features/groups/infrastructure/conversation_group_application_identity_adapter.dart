import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';

final class ConversationGroupApplicationIdentityAdapter
    implements GroupApplicationIdentityPort {
  const ConversationGroupApplicationIdentityAdapter(this.delegate);

  final ConversationRepositoryPort delegate;

  @override
  Future<Result<int>> reserveSenderCounter(String deviceId) =>
      delegate.reserveSenderCounter(deviceId);
}
