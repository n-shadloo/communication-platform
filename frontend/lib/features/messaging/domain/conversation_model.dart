import 'dart:typed_data';

import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';

enum ConversationKind { direct, group, saved }

enum MessageTransportState {
  localOnly,
  queued,
  sending,
  relayAccepted,
  partiallyAccepted,
  permanentlyFailed,
  received,
}

enum MessageReceiptState { none, delivered, read }

enum MessageTimestampState { plausible, skewed }

enum PresenceMeaning { offline, socketOnline }

final class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.kind,
    required this.peerUserId,
    required this.lastMessage,
    required this.lastActivityMs,
    required this.unreadCount,
    required this.mutedUntil,
    required this.draft,
    required this.pinnedMessageIds,
    this.pinned = false,
    this.displayTitle,
  });

  final String conversationId;
  final ConversationKind kind;
  final String? peerUserId;
  final String? lastMessage;
  final int lastActivityMs;
  final int unreadCount;
  final DateTime? mutedUntil;
  final String? draft;
  final Set<String> pinnedMessageIds;
  final bool pinned;
  final String? displayTitle;

  bool isMutedAt(DateTime now) =>
      mutedUntil != null && mutedUntil!.isAfter(now);
}

final class MessageReaction {
  const MessageReaction({required this.reactingUserId, required this.emoji});

  final String reactingUserId;
  final String emoji;
}

final class ConversationMessage {
  const ConversationMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.text,
    this.attachments = const [],
    this.attachmentStates = const [],
    required this.replyToMessageId,
    required this.quoteFallback,
    required this.createdMs,
    required this.orderingMs,
    required this.timestampState,
    required this.revision,
    required this.edited,
    required this.deletedForEveryone,
    required this.deletedForMe,
    required this.pinned,
    this.starred = false,
    required this.unread,
    required this.transportState,
    required this.receiptState,
    required this.reactions,
  });

  final String messageId;
  final String conversationId;
  final String senderUserId;
  final String senderDeviceId;
  final String? text;
  final List<EncryptedAttachmentDescriptor> attachments;
  final List<AttachmentTransferState> attachmentStates;
  final String? replyToMessageId;
  final String? quoteFallback;
  final int createdMs;
  final int orderingMs;
  final MessageTimestampState timestampState;
  final int revision;
  final bool edited;
  final bool deletedForEveryone;
  final bool deletedForMe;
  final bool pinned;
  final bool starred;
  final bool unread;
  final MessageTransportState transportState;
  final MessageReceiptState receiptState;
  final List<MessageReaction> reactions;
}

sealed class ConversationTarget {
  const ConversationTarget();
}

final class DirectConversationTarget extends ConversationTarget {
  const DirectConversationTarget(this.peerUserId);

  final String peerUserId;
}

final class SavedConversationTarget extends ConversationTarget {
  const SavedConversationTarget();
}

final class ResolvedApplicationConversation {
  const ResolvedApplicationConversation({
    required this.kind,
    required this.peerUserId,
  });

  final ConversationKind kind;
  final String? peerUserId;
}

final class SendMessageOutcome {
  SendMessageOutcome({
    required Uint8List eventId,
    required Uint8List conversationId,
    required this.transportState,
  }) : eventId = Uint8List.fromList(eventId),
       conversationId = Uint8List.fromList(conversationId);

  final Uint8List eventId;
  final Uint8List conversationId;
  final MessageTransportState transportState;
}

final class PendingDeliveredReceipt {
  const PendingDeliveredReceipt({
    required this.messageId,
    required this.conversationId,
    required this.targetUserId,
    required this.localDeviceId,
  });

  final String messageId;
  final String conversationId;
  final String targetUserId;
  final String localDeviceId;
}

final class TypingProjection {
  const TypingProjection({
    required this.conversationId,
    required this.userId,
    required this.deviceId,
    required this.expiresAt,
  });

  final String conversationId;
  final String userId;
  final String deviceId;
  final DateTime expiresAt;
}

final class PresenceProjection {
  const PresenceProjection({
    required this.userId,
    required this.onlineDeviceCount,
  });

  final String userId;
  final int onlineDeviceCount;

  PresenceMeaning get meaning => onlineDeviceCount > 0
      ? PresenceMeaning.socketOnline
      : PresenceMeaning.offline;
}
