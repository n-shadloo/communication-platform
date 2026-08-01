import 'dart:convert';

import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:drift/drift.dart';

enum ApplicationApplyDisposition {
  applied,
  duplicate,
  eventIdConflict,
  senderCounterRollback,
  policyRejected,
}

final class ApplicationApplyResult {
  const ApplicationApplyResult({
    required this.disposition,
    required this.eventId,
  });

  final ApplicationApplyDisposition disposition;
  final String eventId;
}

/// Executes only inside an existing Drift transaction owned by send/receive.
///
/// Projection rebuilds use the complete authenticated fact set, never arrival
/// order, so late dependencies and counter conflicts deterministically converge.
final class DriftApplicationEventProjector {
  const DriftApplicationEventProjector(this.database);

  static const int maximumFutureClockSkewMs = 5 * 60 * 1000;
  static const int earliestPlausibleTimestampMs = 946684800000;

  static const int _stateCandidate = 0;
  static const int _stateEventIdConflict = 1;
  static const int _stateCounterConflict = 2;
  static const int _stateConversationRejected = 3;

  static const int _quarantineEventIdConflict = 10;
  static const int _quarantineCounterRollback = 11;
  static const int _quarantineConversationPolicy = 12;
  static const int _quarantineMessageIdCollision = 14;

  final LocalDatabase database;

  Future<ApplicationApplyResult> applyInsideTransaction(
    ApplicationEventCommit commit,
  ) async {
    final event = commit.event;
    final eventId = protocolBytesToHex(event.eventId);
    if (!_validCommit(commit)) {
      await _quarantine(_quarantineConversationPolicy, event.eventId);
      return ApplicationApplyResult(
        disposition: ApplicationApplyDisposition.policyRejected,
        eventId: eventId,
      );
    }

    final retained = await (database.select(
      database.unsupportedApplicationEvents,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (retained != null) {
      if (_same(retained.retainedPayload, commit.canonicalBytes)) {
        await (database.delete(
          database.unsupportedApplicationEvents,
        )..where((row) => row.recordKey.equals(retained.recordKey))).go();
      } else {
        await (database.update(
          database.unsupportedApplicationEvents,
        )..where((row) => row.recordKey.equals(retained.recordKey))).write(
          const UnsupportedApplicationEventsCompanion(
            applyState: Value(_stateEventIdConflict),
          ),
        );
        await _quarantine(_quarantineEventIdConflict, event.eventId);
        return ApplicationApplyResult(
          disposition: ApplicationApplyDisposition.eventIdConflict,
          eventId: eventId,
        );
      }
    }

    final existing = await (database.select(
      database.storedApplicationEvents,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (existing != null) {
      if (_same(existing.canonicalEvent, commit.canonicalBytes)) {
        return ApplicationApplyResult(
          disposition: ApplicationApplyDisposition.duplicate,
          eventId: eventId,
        );
      }
      await (database.update(
        database.storedApplicationEvents,
      )..where((row) => row.eventId.equals(eventId))).write(
        const StoredApplicationEventsCompanion(
          applyState: Value(_stateEventIdConflict),
        ),
      );
      await _quarantine(_quarantineEventIdConflict, event.eventId);
      await _rebuildConversation(
        existing.conversationId,
        currentUserId: commit.currentUserId,
      );
      return ApplicationApplyResult(
        disposition: ApplicationApplyDisposition.eventIdConflict,
        eventId: eventId,
      );
    }

    final conversationId = protocolBytesToHex(event.conversationId);
    final peerUserId = commit.peerUserId?.toLowerCase();
    final currentConversation =
        await (database.select(database.conversations)
              ..where((row) => row.conversationId.equals(conversationId)))
            .getSingleOrNull();
    if (currentConversation != null &&
        (currentConversation.kind != commit.conversationKind ||
            currentConversation.peerUserId != peerUserId)) {
      await _insertEvent(
        commit,
        applyState: _stateConversationRejected,
        orderingMs: 0,
      );
      await _quarantine(_quarantineConversationPolicy, event.eventId);
      return ApplicationApplyResult(
        disposition: ApplicationApplyDisposition.policyRejected,
        eventId: eventId,
      );
    }
    if (currentConversation == null) {
      await database
          .into(database.conversations)
          .insert(
            ConversationsCompanion.insert(
              conversationId: conversationId,
              kind: commit.conversationKind,
              listProjectionCiphertext: Uint8List(0),
              sortKey: 0,
              peerUserId: Value(peerUserId),
            ),
          );
    }

    final orderingMs = _orderingTimestamp(event, commit.authenticatedAt);
    await _insertEvent(
      commit,
      applyState: _stateCandidate,
      orderingMs: orderingMs,
    );

    final collisions =
        await (database.select(database.storedApplicationEvents)..where(
              (row) =>
                  row.senderDeviceId.equals(
                    protocolUuidString(event.senderDeviceId),
                  ) &
                  row.senderCounter.equals(event.senderCounter),
            ))
            .get();
    final unsupportedCollisions =
        await (database.select(database.unsupportedApplicationEvents)..where(
              (row) =>
                  row.senderDeviceId.equals(
                    protocolUuidString(event.senderDeviceId),
                  ) &
                  row.senderCounter.equals(event.senderCounter),
            ))
            .get();
    final affectedConversations = <String>{conversationId};
    var rollback = false;
    final collidingEventIds = <String>{
      ...collisions.map((row) => row.eventId),
      ...unsupportedCollisions.map((row) => row.eventId).whereType<String>(),
    };
    if (collidingEventIds.length > 1) {
      rollback = true;
      affectedConversations.addAll(collisions.map((row) => row.conversationId));
      await (database.update(database.storedApplicationEvents)..where(
            (row) =>
                row.senderDeviceId.equals(
                  protocolUuidString(event.senderDeviceId),
                ) &
                row.senderCounter.equals(event.senderCounter),
          ))
          .write(
            const StoredApplicationEventsCompanion(
              applyState: Value(_stateCounterConflict),
            ),
          );
      await (database.update(database.unsupportedApplicationEvents)..where(
            (row) =>
                row.senderDeviceId.equals(
                  protocolUuidString(event.senderDeviceId),
                ) &
                row.senderCounter.equals(event.senderCounter),
          ))
          .write(
            const UnsupportedApplicationEventsCompanion(
              applyState: Value(_stateCounterConflict),
            ),
          );
      await _quarantine(_quarantineCounterRollback, event.eventId);
    }

    for (final affectedConversation in affectedConversations) {
      await _rebuildConversation(
        affectedConversation,
        currentUserId: commit.currentUserId,
      );
    }
    return ApplicationApplyResult(
      disposition: rollback
          ? ApplicationApplyDisposition.senderCounterRollback
          : ApplicationApplyDisposition.applied,
      eventId: eventId,
    );
  }

  Future<void> retainUnsupportedInsideTransaction(
    UnsupportedApplicationCommit commit,
  ) async {
    if (commit.retainedBytes.isEmpty ||
        commit.retainedBytes.length >
            ApplicationMessageProtocolV1.maximumApplicationBytes) {
      throw const FormatException('invalid unsupported event');
    }
    final eventId = commit.eventId == null
        ? null
        : protocolBytesToHex(commit.eventId!);
    final conversationId = commit.conversationId == null
        ? null
        : protocolBytesToHex(commit.conversationId!);
    final existing =
        await (database.select(database.unsupportedApplicationEvents)..where(
              (row) =>
                  row.recordKey.equals(commit.recordKey) |
                  (eventId == null
                      ? const Constant(false)
                      : row.eventId.equals(eventId)),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (_same(existing.retainedPayload, commit.retainedBytes)) {
        return;
      }
      await (database.update(
        database.unsupportedApplicationEvents,
      )..where((row) => row.recordKey.equals(existing.recordKey))).write(
        const UnsupportedApplicationEventsCompanion(
          applyState: Value(_stateEventIdConflict),
        ),
      );
      await _quarantine(
        _quarantineEventIdConflict,
        commit.eventId ?? Uint8List(0),
      );
      return;
    }

    if (eventId != null) {
      final supported = await (database.select(
        database.storedApplicationEvents,
      )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
      if (supported != null) {
        await (database.update(
          database.storedApplicationEvents,
        )..where((row) => row.eventId.equals(eventId))).write(
          const StoredApplicationEventsCompanion(
            applyState: Value(_stateEventIdConflict),
          ),
        );
        await _quarantine(
          _quarantineEventIdConflict,
          commit.eventId ?? Uint8List(0),
        );
        await _rebuildConversation(
          supported.conversationId,
          currentUserId: commit.currentUserId ?? supported.senderUserId,
        );
        return;
      }
    }
    await database
        .into(database.unsupportedApplicationEvents)
        .insert(
          UnsupportedApplicationEventsCompanion.insert(
            recordKey: commit.recordKey,
            eventId: Value(eventId),
            conversationId: Value(conversationId),
            version: commit.version,
            kind: Value(commit.kindValue),
            senderUserId: commit.senderUserId.toLowerCase(),
            senderDeviceId: commit.senderDeviceId.toLowerCase(),
            senderCounter: Value(commit.senderCounter),
            retainedPayload: commit.retainedBytes,
            authenticatedAt: Value(commit.authenticatedAt),
          ),
        );

    if (eventId != null && commit.senderCounter != null) {
      final supportedCollisions =
          await (database.select(database.storedApplicationEvents)..where(
                (row) =>
                    row.senderDeviceId.equals(
                      commit.senderDeviceId.toLowerCase(),
                    ) &
                    row.senderCounter.equals(commit.senderCounter!),
              ))
              .get();
      final unsupportedCollisions =
          await (database.select(database.unsupportedApplicationEvents)..where(
                (row) =>
                    row.senderDeviceId.equals(
                      commit.senderDeviceId.toLowerCase(),
                    ) &
                    row.senderCounter.equals(commit.senderCounter!),
              ))
              .get();
      final eventIds = <String>{
        ...supportedCollisions.map((row) => row.eventId),
        ...unsupportedCollisions.map((row) => row.eventId).whereType<String>(),
      };
      if (eventIds.length > 1) {
        await (database.update(database.storedApplicationEvents)..where(
              (row) =>
                  row.senderDeviceId.equals(
                    commit.senderDeviceId.toLowerCase(),
                  ) &
                  row.senderCounter.equals(commit.senderCounter!),
            ))
            .write(
              const StoredApplicationEventsCompanion(
                applyState: Value(_stateCounterConflict),
              ),
            );
        await (database.update(database.unsupportedApplicationEvents)..where(
              (row) =>
                  row.senderDeviceId.equals(
                    commit.senderDeviceId.toLowerCase(),
                  ) &
                  row.senderCounter.equals(commit.senderCounter!),
            ))
            .write(
              const UnsupportedApplicationEventsCompanion(
                applyState: Value(_stateCounterConflict),
              ),
            );
        await _quarantine(
          _quarantineCounterRollback,
          commit.eventId ?? Uint8List(0),
        );
        for (final affected
            in supportedCollisions.map((row) => row.conversationId).toSet()) {
          await _rebuildConversation(
            affected,
            currentUserId:
                commit.currentUserId ?? supportedCollisions.first.senderUserId,
          );
        }
      }
    }
    await database.customStatement(
      'DELETE FROM unsupported_application_events WHERE record_key NOT IN '
      '(SELECT record_key FROM unsupported_application_events '
      'ORDER BY authenticated_at DESC, record_key DESC LIMIT 256)',
    );
  }

  Future<void> refreshTransportForEventInsideTransaction(String eventId) async {
    final event = await (database.select(
      database.storedApplicationEvents,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (event == null) {
      return;
    }
    await _rebuildConversation(
      event.conversationId,
      currentUserId: event.senderUserId,
    );
  }

  Future<void> _insertEvent(
    ApplicationEventCommit commit, {
    required int applyState,
    required int orderingMs,
  }) async {
    final event = commit.event;
    final body = _encodeBody(event.body, event.references);
    await database
        .into(database.storedApplicationEvents)
        .insert(
          StoredApplicationEventsCompanion.insert(
            eventId: protocolBytesToHex(event.eventId),
            conversationId: protocolBytesToHex(event.conversationId),
            kind: event.kindValue,
            senderUserId: protocolUuidString(event.senderUserId),
            senderDeviceId: protocolUuidString(event.senderDeviceId),
            senderCounter: event.senderCounter,
            createdMs: event.createdMs,
            orderingMs: orderingMs,
            canonicalEvent: commit.canonicalBytes,
            bodyProjection: body,
            applyState: applyState,
            localOrigin: Value(commit.localOrigin),
            localDeviceId: Value(commit.currentDeviceId.toLowerCase()),
            targetMessageId: Value(_targetMessageId(event.body)),
            revision: Value(_revision(event.body)),
            authenticatedAt: Value(commit.authenticatedAt),
          ),
        );
  }

  Future<void> _rebuildConversation(
    String conversationId, {
    required String currentUserId,
  }) async {
    final conversation =
        await (database.select(database.conversations)
              ..where((row) => row.conversationId.equals(conversationId)))
            .getSingleOrNull();
    if (conversation == null) {
      return;
    }
    final events =
        await (database.select(database.storedApplicationEvents)..where(
              (row) =>
                  row.conversationId.equals(conversationId) &
                  row.applyState.equals(_stateCandidate),
            ))
            .get();
    final facts = <_EventFact>[];
    for (final row in events) {
      try {
        facts.add(_EventFact(row: row, body: _decodeBody(row)));
      } on Object {
        await (database.update(
          database.storedApplicationEvents,
        )..where((item) => item.eventId.equals(row.eventId))).write(
          const StoredApplicationEventsCompanion(
            applyState: Value(_stateConversationRejected),
          ),
        );
      }
    }

    final oldMessages = await (database.select(
      database.messages,
    )..where((row) => row.conversationId.equals(conversationId))).get();
    final localState = <String, _LocalMessageState>{
      for (final message in oldMessages)
        message.messageId: _LocalMessageState(
          deletedForMe: message.deletedForMe,
          unread: message.unread,
        ),
    };

    final createsByMessage = <String, List<_EventFact>>{};
    for (final fact in facts.where(
      (fact) => fact.row.kind == ApplicationEventKind.messageCreate.wireValue,
    )) {
      final messageId = fact.body['message_id'] as String;
      (createsByMessage[messageId] ??= []).add(fact);
    }

    var unreadCount = 0;
    _ProjectedMessage? latest;
    final projectedMessageIds = <String>{};
    for (final entry in createsByMessage.entries) {
      if (entry.value.length != 1) {
        for (final collision in entry.value) {
          await _quarantine(
            _quarantineMessageIdCollision,
            _hexToBytes(collision.row.eventId),
          );
        }
        continue;
      }
      final create = entry.value.single;
      if (!_referencesAreValid(create)) {
        continue;
      }
      final projected = await _projectMessage(
        conversation: conversation,
        create: create,
        facts: facts,
        currentUserId: currentUserId.toLowerCase(),
        localState: localState[entry.key],
      );
      await _writeMessage(projected);
      projectedMessageIds.add(projected.messageId);
      if (projected.unread) {
        unreadCount += 1;
      }
      if (latest == null || _compareProjected(projected, latest) > 0) {
        latest = projected;
      }
    }
    final staleMessages = database.delete(database.messages)
      ..where((row) => row.conversationId.equals(conversationId));
    if (projectedMessageIds.isNotEmpty) {
      staleMessages.where((row) => row.messageId.isNotIn(projectedMessageIds));
    }
    await staleMessages.go();
    await (database.update(
      database.conversations,
    )..where((row) => row.conversationId.equals(conversationId))).write(
      ConversationsCompanion(
        listProjectionCiphertext: Value(
          latest?.displayText == null
              ? Uint8List(0)
              : Uint8List.fromList(utf8.encode(latest!.displayText!)),
        ),
        sortKey: Value(latest?.orderingMs ?? 0),
        lastActivityEventId: Value(latest?.orderingEventId),
        unreadCount: Value(unreadCount),
      ),
    );
  }

  Future<_ProjectedMessage> _projectMessage({
    required Conversation conversation,
    required _EventFact create,
    required List<_EventFact> facts,
    required String currentUserId,
    required _LocalMessageState? localState,
  }) async {
    final messageId = create.body['message_id']! as String;
    final senderUserId = create.row.senderUserId;
    final mutations = facts.where(
      (fact) => fact.row.targetMessageId == messageId,
    );
    final edits =
        mutations
            .where(
              (fact) =>
                  fact.row.kind == ApplicationEventKind.messageEdit.wireValue &&
                  fact.row.senderUserId == senderUserId &&
                  _referencesAreValid(fact),
            )
            .toList()
          ..sort(_compareEditFacts);
    final winnerEdit = edits.isEmpty ? null : edits.last;
    final deletes = mutations.where(
      (fact) =>
          fact.row.kind == ApplicationEventKind.messageDelete.wireValue &&
          _referencesAreValid(fact) &&
          (fact.row.senderUserId == senderUserId ||
              _authorizedGroupModerator(conversation, fact.row.senderUserId)),
    );
    final deletedForEveryone = deletes.isNotEmpty;

    final pinFacts =
        mutations
            .where(
              (fact) =>
                  fact.row.kind == ApplicationEventKind.pinSet.wireValue &&
                  _referencesAreValid(fact) &&
                  _authorizedPin(
                    conversation,
                    fact.row.senderUserId,
                    currentUserId,
                  ),
            )
            .toList()
          ..sort(_compareMutationFacts);
    final pinned = pinFacts.isNotEmpty
        ? pinFacts.last.body['pinned']! as bool
        : false;

    final reactionsByUser = <String, List<_EventFact>>{};
    for (final reaction in mutations.where(
      (fact) =>
          fact.row.kind == ApplicationEventKind.reactionSet.wireValue &&
          _referencesAreValid(fact) &&
          _isConversationParticipant(
            conversation,
            fact.row.senderUserId,
            currentUserId,
          ),
    )) {
      (reactionsByUser[reaction.row.senderUserId] ??= []).add(reaction);
    }
    final reactions = <({String userId, String emoji, String eventId})>[];
    for (final entry in reactionsByUser.entries) {
      entry.value.sort(_compareMutationFacts);
      final winner = entry.value.last;
      final emoji = winner.body['emoji'] as String?;
      if (emoji != null) {
        reactions.add((
          userId: entry.key,
          emoji: emoji,
          eventId: winner.row.eventId,
        ));
      }
    }
    reactions.sort((left, right) => left.userId.compareTo(right.userId));

    final receiptStates =
        <({String userId, String deviceId}), MessageReceiptState>{};
    var readOnOwnDevice = false;
    for (final receipt in facts.where(
      (fact) =>
          (fact.row.kind == ApplicationEventKind.receiptDelivered.wireValue ||
              fact.row.kind == ApplicationEventKind.receiptRead.wireValue) &&
          (fact.body['message_ids']! as List<Object?>).contains(messageId) &&
          fact.row.senderUserId != senderUserId &&
          _isConversationParticipant(
            conversation,
            fact.row.senderUserId,
            currentUserId,
          ),
    )) {
      final key = (
        userId: receipt.row.senderUserId,
        deviceId: receipt.row.senderDeviceId,
      );
      final state =
          receipt.row.kind == ApplicationEventKind.receiptRead.wireValue
          ? MessageReceiptState.read
          : MessageReceiptState.delivered;
      final previous = receiptStates[key];
      if (previous == null || state.index > previous.index) {
        receiptStates[key] = state;
      }
      if (state == MessageReceiptState.read) {
        readOnOwnDevice |= receipt.row.senderUserId == currentUserId;
      }
    }
    final receipts =
        [
          for (final entry in receiptStates.entries)
            _ProjectedReceipt(
              userId: entry.key.userId,
              deviceId: entry.key.deviceId,
              state: entry.value,
            ),
        ]..sort((left, right) {
          final user = left.userId.compareTo(right.userId);
          return user != 0 ? user : left.deviceId.compareTo(right.deviceId);
        });
    final receiptState = receipts.fold(
      MessageReceiptState.none,
      (state, receipt) =>
          receipt.state.index > state.index ? receipt.state : state,
    );

    final text =
        winnerEdit?.body['text'] as String? ?? create.body['text']! as String;
    final attachments =
        (create.body['attachments'] as List<Object?>?)
            ?.whereType<Map<String, Object?>>()
            .toList(growable: false) ??
        const <Map<String, Object?>>[];
    final revision = winnerEdit?.row.revision ?? 0;
    final currentEventId = winnerEdit?.row.eventId ?? create.row.eventId;
    var unread =
        localState?.unread ??
        (!create.row.localOrigin &&
            senderUserId != currentUserId &&
            conversation.kind != ConversationKind.saved.index);
    if (readOnOwnDevice) {
      unread = false;
    }
    final transport = await _transportState(create);
    return _ProjectedMessage(
      messageId: messageId,
      conversationId: conversation.conversationId,
      currentEventId: currentEventId,
      senderUserId: senderUserId,
      senderDeviceId: create.row.senderDeviceId,
      text: deletedForEveryone ? null : text,
      attachments: deletedForEveryone ? const [] : attachments,
      replyToMessageId: create.body['reply_to'] as String?,
      quoteFallback: create.body['quote'] as String?,
      status: transport,
      receiptState: receiptState,
      revision: revision,
      createdMs: create.row.createdMs,
      orderingMs: create.row.orderingMs,
      orderingEventId: create.row.eventId,
      timestampState: create.row.orderingMs == 0
          ? MessageTimestampState.skewed
          : MessageTimestampState.plausible,
      edited: winnerEdit != null,
      deletedForEveryone: deletedForEveryone,
      deletedForMe: localState?.deletedForMe ?? false,
      pinned: pinned,
      unread: unread,
      reactions: reactions,
      receipts: receipts,
      pendingDeliveredReceipt:
          !create.row.localOrigin &&
          senderUserId != currentUserId &&
          conversation.kind == ConversationKind.direct.index,
      receiptTargetUserId: senderUserId,
      localDeviceId: create.row.localDeviceId,
    );
  }

  Future<void> _writeMessage(_ProjectedMessage message) async {
    final createdAtMs =
        message.timestampState == MessageTimestampState.plausible
        ? message.createdMs
        : 0;
    await database
        .into(database.messages)
        .insertOnConflictUpdate(
          MessagesCompanion.insert(
            messageId: message.messageId,
            conversationId: message.conversationId,
            currentEventId: message.currentEventId,
            projectionCiphertext: message.text == null
                ? Uint8List(0)
                : Uint8List.fromList(utf8.encode(message.text!)),
            status: message.status.index,
            revision: message.revision,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              createdAtMs,
              isUtc: true,
            ),
            senderUserId: Value(message.senderUserId),
            senderDeviceId: Value(message.senderDeviceId),
            replyToMessageId: Value(message.replyToMessageId),
            quoteFallbackCiphertext: Value(
              message.quoteFallback == null
                  ? null
                  : Uint8List.fromList(utf8.encode(message.quoteFallback!)),
            ),
            orderingMs: Value(message.orderingMs),
            orderingEventId: Value(message.orderingEventId),
            timestampState: Value(message.timestampState.index),
            deletedForEveryone: Value(message.deletedForEveryone),
            deletedForMe: Value(message.deletedForMe),
            pinned: Value(message.pinned),
            unread: Value(message.unread),
          ),
        );
    if (message.attachments.isNotEmpty) {
      await (database.delete(
        database.attachments,
      )..where((row) => row.messageId.equals(message.messageId))).go();
      for (final attachment in message.attachments) {
        final id = attachment['capability'];
        if (id is! String) continue;
        await database
            .into(database.attachments)
            .insertOnConflictUpdate(
              AttachmentsCompanion.insert(
                attachmentId: id,
                messageId: message.messageId,
                encryptedDescriptor: Uint8List.fromList(
                  utf8.encode(jsonEncode(attachment)),
                ),
                transferState: AttachmentTransferState.queued.index,
              ),
            );
      }
    }
    await (database.delete(
      database.messageReactions,
    )..where((row) => row.messageId.equals(message.messageId))).go();
    await (database.delete(
      database.receipts,
    )..where((row) => row.messageId.equals(message.messageId))).go();
    for (final reaction in message.reactions) {
      await database
          .into(database.messageReactions)
          .insert(
            MessageReactionsCompanion.insert(
              messageId: message.messageId,
              reactingUserId: reaction.userId,
              eventId: reaction.eventId,
              emojiCiphertext: Value(
                Uint8List.fromList(utf8.encode(reaction.emoji)),
              ),
            ),
          );
    }
    for (final receipt in message.receipts) {
      await database
          .into(database.receipts)
          .insert(
            ReceiptsCompanion.insert(
              messageId: message.messageId,
              userId: receipt.userId,
              deviceId: receipt.deviceId,
              receiptState: receipt.state.index,
              projectionCiphertext: Uint8List(0),
            ),
          );
    }
    if (message.deletedForEveryone) {
      await (database.update(
        database.attachments,
      )..where((row) => row.messageId.equals(message.messageId))).write(
        const AttachmentsCompanion(
          boundedCacheHandleCiphertext: Value(null),
          cacheExpiresAt: Value(null),
        ),
      );
    }
    if (message.pendingDeliveredReceipt && message.localDeviceId.isNotEmpty) {
      await database
          .into(database.pendingApplicationReceipts)
          .insert(
            PendingApplicationReceiptsCompanion.insert(
              messageId: message.messageId,
              conversationId: message.conversationId,
              targetUserId: message.receiptTargetUserId,
              localDeviceId: message.localDeviceId,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<MessageTransportState> _transportState(_EventFact create) async {
    if (!create.row.localOrigin) {
      return MessageTransportState.received;
    }
    final targets = await (database.select(
      database.outboxOperations,
    )..where((row) => row.eventId.equals(create.row.eventId))).get();
    if (targets.isEmpty) {
      return MessageTransportState.localOnly;
    }
    final states = targets.map((row) => row.attemptState).toList();
    final hasAccepted = states.contains(OutboxAttemptState.accepted.index);
    final hasPending = states.any(
      (state) =>
          state == OutboxAttemptState.queued.index ||
          state == OutboxAttemptState.retryWait.index ||
          state == OutboxAttemptState.sending.index,
    );
    if (hasPending) {
      if (hasAccepted) {
        return MessageTransportState.partiallyAccepted;
      }
      return states.contains(OutboxAttemptState.sending.index)
          ? MessageTransportState.sending
          : MessageTransportState.queued;
    }
    if (states.contains(OutboxAttemptState.permanentlyFailed.index) ||
        !hasAccepted) {
      return MessageTransportState.permanentlyFailed;
    }
    return MessageTransportState.relayAccepted;
  }

  bool _validCommit(ApplicationEventCommit commit) {
    final event = commit.event;
    if (!event.isSupported ||
        event.kind == ApplicationEventKind.typingSet ||
        commit.canonicalBytes.isEmpty ||
        commit.canonicalBytes.length >
            ApplicationMessageProtocolV1.maximumApplicationBytes ||
        commit.conversationKind < 0 ||
        commit.conversationKind >= ConversationKind.values.length ||
        event.createdMs > 8640000000000000 ||
        event.senderCounter > 0x7fffffffffffffff) {
      return false;
    }
    final senderUser = protocolUuidString(event.senderUserId);
    final currentUser = commit.currentUserId.toLowerCase();
    return switch (ConversationKind.values[commit.conversationKind]) {
      ConversationKind.direct =>
        commit.peerUserId != null &&
            commit.peerUserId != currentUser &&
            (senderUser == currentUser ||
                senderUser == commit.peerUserId!.toLowerCase()),
      ConversationKind.saved =>
        commit.peerUserId == null &&
            senderUser == currentUser &&
            event.kind != ApplicationEventKind.messageDelete &&
            event.kind != ApplicationEventKind.receiptDelivered &&
            event.kind != ApplicationEventKind.receiptRead,
      ConversationKind.group => true,
    };
  }

  int _orderingTimestamp(
    ApplicationEventRecord event,
    DateTime authenticatedAt,
  ) {
    final maximum =
        authenticatedAt.toUtc().millisecondsSinceEpoch +
        maximumFutureClockSkewMs;
    return event.createdMs >= earliestPlausibleTimestampMs &&
            event.createdMs <= maximum
        ? event.createdMs
        : 0;
  }

  bool _referencesAreValid(_EventFact fact) {
    final references = (fact.body['references']! as List<Object?>)
        .cast<String>();
    return switch (ApplicationEventKind.fromWireValue(fact.row.kind)) {
      ApplicationEventKind.messageCreate =>
        fact.body['reply_to'] == null ||
            references.contains(fact.body['reply_to']),
      ApplicationEventKind.messageEdit ||
      ApplicationEventKind.messageDelete ||
      ApplicationEventKind.reactionSet ||
      ApplicationEventKind.pinSet => references.contains(fact.body['target']),
      ApplicationEventKind.receiptDelivered ||
      ApplicationEventKind.receiptRead =>
        (fact.body['message_ids']! as List<Object?>).every(references.contains),
      ApplicationEventKind.typingSet || null => true,
    };
  }

  bool _isConversationParticipant(
    Conversation conversation,
    String userId,
    String currentUserId,
  ) {
    if (conversation.kind == ConversationKind.saved.index) {
      return conversation.peerUserId == null && userId == currentUserId;
    }
    if (conversation.kind == ConversationKind.direct.index) {
      return userId == conversation.peerUserId || userId == currentUserId;
    }
    return true;
  }

  bool _authorizedPin(
    Conversation conversation,
    String userId,
    String currentUserId,
  ) {
    if (conversation.kind != ConversationKind.group.index) {
      return _isConversationParticipant(conversation, userId, currentUserId);
    }
    return _authorizedGroupModerator(conversation, userId);
  }

  bool _authorizedGroupModerator(Conversation conversation, String userId) {
    if (conversation.kind != ConversationKind.group.index) {
      return false;
    }
    // Group role projection is established by the later MLS/control piece.
    // Until then no moderator-only mutation is guessed in Dart.
    return false;
  }

  Future<void> _quarantine(int reason, Uint8List digest) async {
    await database
        .into(database.quarantineRecords)
        .insert(
          QuarantineRecordsCompanion.insert(
            reasonCode: reason,
            opaqueDigest: Uint8List.fromList(digest.take(32).toList()),
          ),
        );
    await database.customStatement(
      'DELETE FROM quarantine WHERE id NOT IN '
      '(SELECT id FROM quarantine ORDER BY received_at DESC, id DESC LIMIT 256)',
    );
  }
}

final class _EventFact {
  const _EventFact({required this.row, required this.body});

  final StoredApplicationEvent row;
  final Map<String, Object?> body;
}

final class _LocalMessageState {
  const _LocalMessageState({required this.deletedForMe, required this.unread});

  final bool deletedForMe;
  final bool unread;
}

final class _ProjectedMessage {
  const _ProjectedMessage({
    required this.messageId,
    required this.conversationId,
    required this.currentEventId,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.text,
    required this.attachments,
    required this.replyToMessageId,
    required this.quoteFallback,
    required this.status,
    required this.receiptState,
    required this.revision,
    required this.createdMs,
    required this.orderingMs,
    required this.orderingEventId,
    required this.timestampState,
    required this.edited,
    required this.deletedForEveryone,
    required this.deletedForMe,
    required this.pinned,
    required this.unread,
    required this.reactions,
    required this.receipts,
    required this.pendingDeliveredReceipt,
    required this.receiptTargetUserId,
    required this.localDeviceId,
  });

  final String messageId;
  final String conversationId;
  final String currentEventId;
  final String senderUserId;
  final String senderDeviceId;
  final String? text;
  final List<Map<String, Object?>> attachments;
  final String? replyToMessageId;
  final String? quoteFallback;
  final MessageTransportState status;
  final MessageReceiptState receiptState;
  final int revision;
  final int createdMs;
  final int orderingMs;
  final String orderingEventId;
  final MessageTimestampState timestampState;
  final bool edited;
  final bool deletedForEveryone;
  final bool deletedForMe;
  final bool pinned;
  final bool unread;
  final List<({String userId, String emoji, String eventId})> reactions;
  final List<_ProjectedReceipt> receipts;
  final bool pendingDeliveredReceipt;
  final String receiptTargetUserId;
  final String localDeviceId;

  String? get displayText => deletedForEveryone ? null : text;
}

final class _ProjectedReceipt {
  const _ProjectedReceipt({
    required this.userId,
    required this.deviceId,
    required this.state,
  });

  final String userId;
  final String deviceId;
  final MessageReceiptState state;
}

int _compareProjected(_ProjectedMessage left, _ProjectedMessage right) {
  final timestamp = left.orderingMs.compareTo(right.orderingMs);
  return timestamp != 0
      ? timestamp
      : left.orderingEventId.compareTo(right.orderingEventId);
}

int _compareEditFacts(_EventFact left, _EventFact right) {
  final revision = left.row.revision!.compareTo(right.row.revision!);
  if (revision != 0) {
    return revision;
  }
  return _compareMutationFacts(left, right);
}

int _compareMutationFacts(_EventFact left, _EventFact right) {
  final counter = left.row.senderCounter.compareTo(right.row.senderCounter);
  return counter != 0 ? counter : left.row.eventId.compareTo(right.row.eventId);
}

Uint8List _encodeBody(ApplicationEventBody body, List<Uint8List> references) {
  final Map<String, Object?> value = switch (body) {
    MessageCreateBody() => {
      'message_id': protocolBytesToHex(body.messageId),
      'text': body.text,
      'content_type': body.contentType.index,
      'attachments': [
        for (final attachment in body.attachments)
          <String, Object?>{
            'capability': attachment.capabilityId,
            'key': base64UrlEncode(attachment.key),
            'header': base64UrlEncode(attachment.header),
            'stream_header': base64UrlEncode(attachment.secretstreamHeader),
            'encrypted_size': attachment.encryptedSize,
            'bucket_size': attachment.bucketSize,
            'plaintext_size': attachment.plaintextSize,
            'name': attachment.displayName,
            'mime': attachment.mimeType,
            'media_kind': attachment.mediaKind.index,
            'width': attachment.width,
            'height': attachment.height,
            'caption': attachment.caption,
            'thumbnail': attachment.thumbnail == null
                ? null
                : base64UrlEncode(attachment.thumbnail!),
          },
      ],
      'reply_to': body.replyToMessageId == null
          ? null
          : protocolBytesToHex(body.replyToMessageId!),
      'quote': body.quoteFallback,
    },
    MessageEditBody() => {
      'target': protocolBytesToHex(body.targetMessageId),
      'text': body.replacementText,
      'revision': body.revision,
    },
    MessageDeleteBody() => {'target': protocolBytesToHex(body.targetMessageId)},
    ReactionSetBody() => {
      'target': protocolBytesToHex(body.targetMessageId),
      'emoji': body.emoji,
    },
    PinSetBody() => {
      'target': protocolBytesToHex(body.targetMessageId),
      'pinned': body.pinned,
    },
    ReceiptBody() => {
      'message_ids': [for (final id in body.messageIds) protocolBytesToHex(id)],
    },
    TypingSetBody() => {
      'is_typing': body.isTyping,
      'expires_ms': body.expiresMs,
    },
    UnsupportedEventBody() => throw const FormatException(
      'unsupported event cannot be projected',
    ),
  };
  value['references'] = [
    for (final reference in references) protocolBytesToHex(reference),
  ];
  return Uint8List.fromList(utf8.encode(jsonEncode(value)));
}

Map<String, Object?> _decodeBody(StoredApplicationEvent row) {
  final decoded =
      jsonDecode(utf8.decode(row.bodyProjection, allowMalformed: false))
          as Map<String, Object?>;
  return decoded;
}

String? _targetMessageId(ApplicationEventBody body) => switch (body) {
  MessageEditBody() => protocolBytesToHex(body.targetMessageId),
  MessageDeleteBody() => protocolBytesToHex(body.targetMessageId),
  ReactionSetBody() => protocolBytesToHex(body.targetMessageId),
  PinSetBody() => protocolBytesToHex(body.targetMessageId),
  _ => null,
};

int? _revision(ApplicationEventBody body) => switch (body) {
  MessageEditBody() => body.revision,
  _ => null,
};

Uint8List _hexToBytes(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

bool _same(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
