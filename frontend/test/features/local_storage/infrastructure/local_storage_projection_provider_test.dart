import 'dart:async';
import 'dart:typed_data';

import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/drift_conversation_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Riverpod projection reacts to committed Drift state only', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWith((ref) => Future.value(database)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final initial = Completer<List<ConversationProjection>>();
    final committed = Completer<List<ConversationProjection>>();
    final subscription = container.listen(conversationProjectionsProvider, (
      previous,
      next,
    ) {
      if (next case AsyncData(value: final rows)) {
        if (rows.isEmpty && !initial.isCompleted) initial.complete(rows);
        if (rows.isNotEmpty && !committed.isCompleted) {
          committed.complete(rows);
        }
      }
    }, fireImmediately: true);
    expect(await initial.future.timeout(const Duration(seconds: 2)), isEmpty);

    final repository = DriftConversationProjectionRepository(database);
    await repository.applyAuthenticatedEvent(
      StoredMessageEvent(
        eventId: 'event-provider',
        messageId: 'message-provider',
        conversationId: 'conversation-provider',
        eventKind: 0,
        authenticatedCiphertext: Uint8List.fromList([1, 3, 5]),
        messageStatus: 0,
        revision: 0,
        createdAt: DateTime.utc(2026, 7, 27),
        conversationKind: 0,
        conversationProjectionCiphertext: Uint8List.fromList([2, 4, 6]),
        sortKey: 10,
      ),
    );

    final rows = await committed.future.timeout(const Duration(seconds: 2));
    expect(rows.single.conversationId, 'conversation-provider');
    expect(rows.single.authenticatedCiphertext, Uint8List.fromList([2, 4, 6]));
    subscription.close();
  });
}
