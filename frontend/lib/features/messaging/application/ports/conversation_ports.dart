import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';

abstract interface class ConversationRepositoryPort implements RepositoryPort {
  Stream<List<ConversationSummary>> watchConversations(String currentUserId);

  Stream<List<ConversationMessage>> watchMessages({
    required String currentUserId,
    required String conversationId,
  });

  Future<Result<int>> reserveSenderCounter(String deviceId);

  Future<Result<int>> nextEditRevision({
    required String messageId,
    required String senderUserId,
  });

  Future<Result<void>> requireOriginalSender({
    required String messageId,
    required String senderUserId,
  });

  Future<Result<ConversationSummary?>> readConversation(String conversationId);

  Future<Result<void>> saveDraft({
    required String conversationId,
    required String? text,
  });

  Future<Result<void>> setMutedUntil({
    required String conversationId,
    required DateTime? mutedUntil,
  });

  Future<Result<void>> deleteForMe(String messageId);

  Future<Result<List<String>>> markConversationRead(String conversationId);

  Future<Result<List<PendingDeliveredReceipt>>> readPendingDeliveredReceipts({
    required int limit,
  });

  Future<Result<void>> completePendingDeliveredReceipts({
    required String localDeviceId,
    required List<String> messageIds,
  });
}

abstract interface class ApplicationConversationResolverPort implements Port {
  Future<Result<ResolvedApplicationConversation>> resolve({
    required ApplicationEventRecord event,
    required String currentUserId,
  });
}

final class ApplicationFanoutOutcome {
  const ApplicationFanoutOutcome({required this.targetCount});

  final int targetCount;
}

abstract interface class ApplicationFanoutPort implements Port {
  Future<Result<ApplicationFanoutOutcome>> prepareAndQueue({
    required String operationId,
    required String eventId,
    required String currentUserId,
    required String currentDeviceId,
    required String peerUserId,
    required Uint8List openedPayload,
    required ApplicationEventCommit applicationEvent,
  });
}

abstract interface class VolatileConversationStatePort implements Port {
  Stream<List<TypingProjection>> watchTyping(String conversationId);

  Stream<PresenceProjection> watchPresence(String userId);

  void applyTyping({
    required String conversationId,
    required String userId,
    required String deviceId,
    required bool isTyping,
    required DateTime expiresAt,
    required DateTime authenticatedAt,
  });

  void applyPresence({
    required String userId,
    required String deviceId,
    required bool socketOnline,
  });

  void clearDisconnected();
}
