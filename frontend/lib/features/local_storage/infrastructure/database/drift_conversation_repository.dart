import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/drift_repository_base.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';

final class DriftConversationProjectionRepository extends DriftRepositoryBase
    implements ConversationProjectionRepository {
  const DriftConversationProjectionRepository(super.database);

  @override
  Stream<List<ConversationProjection>> watchConversations() {
    return database.watchConversationRows().map(
      (rows) => List.unmodifiable(
        rows.map(
          (row) => ConversationProjection(
            conversationId: row.conversationId,
            kind: row.kind,
            authenticatedCiphertext: row.listProjectionCiphertext,
            sortKey: row.sortKey,
          ),
        ),
      ),
    );
  }

  @override
  Future<Result<bool>> applyAuthenticatedEvent(StoredMessageEvent event) {
    return runWrite(() async {
      final alreadyApplied = await (database.select(
        database.messageEvents,
      )..where((row) => row.eventId.equals(event.eventId))).getSingleOrNull();
      if (alreadyApplied != null) {
        return false;
      }

      await database
          .into(database.conversations)
          .insertOnConflictUpdate(
            ConversationsCompanion.insert(
              conversationId: event.conversationId,
              kind: event.conversationKind,
              listProjectionCiphertext: event.conversationProjectionCiphertext,
              sortKey: event.sortKey,
            ),
          );
      await database
          .into(database.messageEvents)
          .insert(
            MessageEventsCompanion.insert(
              eventId: event.eventId,
              messageId: event.messageId,
              conversationId: event.conversationId,
              eventKind: event.eventKind,
              authenticatedCiphertext: event.authenticatedCiphertext,
              createdAt: event.createdAt,
            ),
          );
      await database
          .into(database.messages)
          .insertOnConflictUpdate(
            MessagesCompanion.insert(
              messageId: event.messageId,
              conversationId: event.conversationId,
              currentEventId: event.eventId,
              projectionCiphertext: event.authenticatedCiphertext,
              status: event.messageStatus,
              revision: event.revision,
              createdAt: event.createdAt,
            ),
          );
      return true;
    });
  }
}
