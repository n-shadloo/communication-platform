import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';

abstract final class ChatViewModelMapper {
  static ChatSecurityGate securityGate(ContactTrustState? state) =>
      switch (state) {
        ContactTrustState.verified => ChatSecurityGate.ready,
        null => ChatSecurityGate.unverifiedIdentity,
        ContactTrustState.unverified || ContactTrustState.identityUnavailable =>
          ChatSecurityGate.unverifiedIdentity,
        ContactTrustState.invalidDevice => ChatSecurityGate.unverifiedDevice,
        ContactTrustState.masterKeyChanged => ChatSecurityGate.masterKeyChanged,
        ContactTrustState.deviceLogFork => ChatSecurityGate.deviceLogFork,
      };

  static List<ChatListItemViewModel> summaries(
    List<ConversationSummary> summaries, {
    required DateTime now,
    required String savedMessagesTitle,
    required String Function(String peerUserId) peerTitle,
  }) {
    final items = [
      for (final summary in summaries)
        ChatListItemViewModel(
          conversationId: summary.conversationId,
          title: summary.kind == ConversationKind.saved
              ? savedMessagesTitle
              : summary.peerUserId == null
              ? summary.conversationId
              : peerTitle(summary.peerUserId!),
          preview: summary.lastMessage ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            summary.lastActivityMs,
            isUtc: true,
          ).toLocal(),
          unreadCount: summary.kind == ConversationKind.saved
              ? 0
              : summary.unreadCount,
          muted: summary.isMutedAt(now),
          pinned: summary.pinned,
          savedMessages: summary.kind == ConversationKind.saved,
          peerUserId: summary.peerUserId,
        ),
    ];
    items.sort((left, right) {
      if (left.pinned != right.pinned) return left.pinned ? -1 : 1;
      return right.timestamp.compareTo(left.timestamp);
    });
    return List.unmodifiable(items);
  }

  static List<ChatMessageViewModel> messages(
    List<ConversationMessage> source, {
    required String currentUserId,
    required String currentUserName,
    required String peerName,
  }) {
    final byId = {for (final message in source) message.messageId: message};
    return List.unmodifiable([
      for (var index = 0; index < source.length; index++)
        _message(
          source[index],
          previous: index == 0 ? null : source[index - 1],
          next: index == source.length - 1 ? null : source[index + 1],
          byId: byId,
          currentUserId: currentUserId,
          currentUserName: currentUserName,
          peerName: peerName,
        ),
    ]);
  }

  static ChatMessageViewModel _message(
    ConversationMessage message, {
    required ConversationMessage? previous,
    required ConversationMessage? next,
    required Map<String, ConversationMessage> byId,
    required String currentUserId,
    required String currentUserName,
    required String peerName,
  }) {
    final outgoing =
        message.senderUserId.toLowerCase() == currentUserId.toLowerCase();
    final groupedWithPrevious = _grouped(previous, message);
    final groupedWithNext = _grouped(message, next);
    final reactionCounts = <String, int>{};
    final ownReactions = <String>{};
    for (final reaction in message.reactions) {
      reactionCounts.update(
        reaction.emoji,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (reaction.reactingUserId.toLowerCase() ==
          currentUserId.toLowerCase()) {
        ownReactions.add(reaction.emoji);
      }
    }
    final reply = message.replyToMessageId == null
        ? null
        : byId[message.replyToMessageId];
    return ChatMessageViewModel(
      id: message.messageId,
      authorId: message.senderUserId,
      authorName: outgoing ? currentUserName : peerName,
      outgoing: outgoing,
      kind: message.attachments.isEmpty
          ? ChatTimelineContentKind.text
          : message.attachments.every((attachment) => attachment.isInlineImage)
          ? ChatTimelineContentKind.image
          : ChatTimelineContentKind.attachment,
      text: message.text,
      attachments: message.attachments,
      attachmentStates: message.attachmentStates,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        message.createdMs,
        isUtc: true,
      ).toLocal(),
      delivery: _delivery(message),
      firstInAuthorGroup: !groupedWithPrevious,
      lastInAuthorGroup: !groupedWithNext,
      edited: message.edited,
      deleted: message.deletedForEveryone || message.deletedForMe,
      pinned: message.pinned,
      starred: message.starred,
      unread: !outgoing && message.unread,
      timestampSkewed: message.timestampState == MessageTimestampState.skewed,
      canEdit: outgoing && !message.deletedForEveryone,
      canDeleteForEveryone: outgoing && !message.deletedForEveryone,
      replyToMessageId: message.replyToMessageId,
      replyAuthor: reply == null
          ? null
          : reply.senderUserId.toLowerCase() == currentUserId.toLowerCase()
          ? currentUserName
          : peerName,
      replyQuote: reply?.text ?? message.quoteFallback,
      reactions: [
        for (final entry in reactionCounts.entries)
          ChatReactionViewModel(
            emoji: entry.key,
            count: entry.value,
            selectedByCurrentUser: ownReactions.contains(entry.key),
          ),
      ],
    );
  }

  static bool _grouped(
    ConversationMessage? first,
    ConversationMessage? second,
  ) {
    if (first == null || second == null) return false;
    return first.senderUserId == second.senderUserId &&
        (second.orderingMs - first.orderingMs).abs() <=
            const Duration(minutes: 5).inMilliseconds;
  }

  static ChatDeliveryViewState _delivery(ConversationMessage message) {
    if (message.transportState == MessageTransportState.received) {
      return ChatDeliveryViewState.received;
    }
    if (message.transportState == MessageTransportState.permanentlyFailed) {
      return ChatDeliveryViewState.failed;
    }
    if (message.receiptState == MessageReceiptState.read) {
      return ChatDeliveryViewState.read;
    }
    if (message.receiptState == MessageReceiptState.delivered) {
      return ChatDeliveryViewState.delivered;
    }
    return switch (message.transportState) {
      MessageTransportState.localOnly => ChatDeliveryViewState.localOnly,
      MessageTransportState.queued => ChatDeliveryViewState.queued,
      MessageTransportState.sending => ChatDeliveryViewState.sending,
      MessageTransportState.relayAccepted ||
      MessageTransportState.partiallyAccepted => ChatDeliveryViewState.accepted,
      MessageTransportState.permanentlyFailed => ChatDeliveryViewState.failed,
      MessageTransportState.received => ChatDeliveryViewState.received,
    };
  }
}
