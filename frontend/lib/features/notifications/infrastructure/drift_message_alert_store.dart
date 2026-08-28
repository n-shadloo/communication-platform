import 'dart:async';
import 'dart:convert';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/notifications/application/ports/message_alert_ports.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:drift/drift.dart';

/// Reads the alert's input straight out of the committed projection.
///
/// It owns no state of its own and duplicates none: unread is
/// `messages.unread`, exactly as the projector wrote it inside the inbox
/// transaction and exactly as marking a conversation read clears it. The only
/// column this feature adds is the one-shot marker.
final class DriftMessageAlertStore implements MessageAlertStorePort {
  const DriftMessageAlertStore(this.database);

  /// One row, one flag. Kept in the encrypted preference table rather than in a
  /// column of its own because it is an installation fact, not a message fact.
  static const permissionRequestedKey = 'notifications.permission_requested.v1';

  final LocalDatabase database;

  @override
  Stream<void> get changes => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.messages,
          database.conversations,
        ]),
      )
      .map<void>((_) {});

  @override
  Future<Result<List<PendingMessageAlert>>> readPending({
    required int limit,
  }) async {
    try {
      final messages = database.messages;
      final conversations = database.conversations;
      final query =
          database.select(messages).join([
            innerJoin(
              conversations,
              conversations.conversationId.equalsExp(messages.conversationId),
            ),
          ])..where(
            messages.unread.equals(true) &
                messages.deletedForMe.equals(false) &
                messages.deletedForEveryone.equals(false) &
                conversations.tombstoned.equals(false) &
                conversations.kind.equals(ConversationKind.saved.index).not(),
          );
      // Rows with an unspent marker come first, so a bounded read after a long
      // absence always makes progress instead of returning the same page every
      // time; newest first within that, so the rows the user is most likely to
      // act on are the ones a bounded page keeps.
      query
        ..orderBy([
          OrderingTerm.asc(messages.alerted),
          OrderingTerm.desc(messages.orderingMs),
          OrderingTerm.desc(messages.messageId),
        ])
        ..limit(limit);
      final rows = await query.get();
      return Result.success([
        for (final row in rows)
          if (row.readTable(messages) case final message)
            PendingMessageAlert(
              messageId: message.messageId,
              conversationId: message.conversationId,
              alerted: message.alerted,
              mutedUntil: row.readTable(conversations).mutedUntil,
            ),
      ]);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> markAlerted(List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return const Result.success(null);
    }
    try {
      await database.writeTransaction(() async {
        await (database.update(database.messages)
              ..where((row) => row.messageId.isIn(messageIds)))
            .write(const MessagesCompanion(alerted: Value(true)));
      });
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<bool>> readPermissionRequested() async {
    try {
      final row =
          await (database.select(database.localPreferences)..where(
                (entry) => entry.preferenceKey.equals(permissionRequestedKey),
              ))
              .getSingleOrNull();
      if (row == null) {
        return const Result.success(false);
      }
      return Result.success(utf8.decode(row.valueCiphertext) == 'true');
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> recordPermissionRequested() async {
    try {
      await database
          .into(database.localPreferences)
          .insertOnConflictUpdate(
            LocalPreferencesCompanion.insert(
              preferenceKey: permissionRequestedKey,
              valueCiphertext: Uint8List.fromList(utf8.encode('true')),
              valueVersion: 1,
            ),
          );
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }
}
