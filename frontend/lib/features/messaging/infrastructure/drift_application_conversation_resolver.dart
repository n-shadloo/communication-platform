import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:drift/drift.dart';

final class DriftApplicationConversationResolver
    implements ApplicationConversationResolverPort {
  const DriftApplicationConversationResolver({
    required this.database,
    required this.protocol,
  });

  final LocalDatabase database;
  final ApplicationProtocolPort protocol;

  @override
  Future<Result<ResolvedApplicationConversation>> resolve({
    required ApplicationEventRecord event,
    required String currentUserId,
  }) async {
    try {
      final current = currentUserId.toLowerCase();
      final currentBytes = protocolUuidBytes(current);
      final conversationId = protocolBytesToHex(event.conversationId);
      final sender = protocolUuidString(event.senderUserId);

      final savedResult = await protocol.deriveSavedConversationId(
        currentBytes,
      );
      if (savedResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      final savedId = protocolBytesToHex(
        (savedResult as Success).value as List<int>,
      );
      if (conversationId == savedId) {
        return sender == current
            ? const Result.success(
                ResolvedApplicationConversation(
                  kind: ConversationKind.saved,
                  peerUserId: null,
                ),
              )
            : const Result.failure(
                SecurityFailure(SecurityFailureKind.unauthenticatedInput),
              );
      }

      final existing =
          await (database.select(database.conversations)
                ..where((row) => row.conversationId.equals(conversationId)))
              .getSingleOrNull();
      if (existing != null) {
        final kind = ConversationKind.values[existing.kind];
        if (kind == ConversationKind.group) {
          return Result.success(
            ResolvedApplicationConversation(kind: kind, peerUserId: null),
          );
        }
        final peer = existing.peerUserId;
        if (kind != ConversationKind.direct ||
            peer == null ||
            (sender != current && sender != peer)) {
          return const Result.failure(
            SecurityFailure(SecurityFailureKind.unauthenticatedInput),
          );
        }
        return Result.success(
          ResolvedApplicationConversation(kind: kind, peerUserId: peer),
        );
      }

      if (sender != current) {
        final derived = await _directId(currentBytes, event.senderUserId);
        return derived == conversationId
            ? Result.success(
                ResolvedApplicationConversation(
                  kind: ConversationKind.direct,
                  peerUserId: sender,
                ),
              )
            : const Result.failure(
                SecurityFailure(SecurityFailureKind.unauthenticatedInput),
              );
      }

      // An own-device copy does not expose the peer outside the encrypted event.
      // Resolve it against the authenticated local directory without adding a
      // participant field to the wire format.
      final users = await (database.select(
        database.users,
      )..where((row) => row.activated.equals(true))).get();
      for (final user in users) {
        if (user.userId == current) {
          continue;
        }
        final candidate = await _directId(
          currentBytes,
          protocolUuidBytes(user.userId),
        );
        if (candidate == conversationId) {
          return Result.success(
            ResolvedApplicationConversation(
              kind: ConversationKind.direct,
              peerUserId: user.userId,
            ),
          );
        }
      }
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
  }

  Future<String> _directId(List<int> first, List<int> second) async {
    final result = await protocol.deriveDirectConversationId(
      firstUserId: Uint8List.fromList(first),
      secondUserId: Uint8List.fromList(second),
    );
    if (result case FailureResult(failure: final failure)) {
      throw _ResolutionFailure(failure);
    }
    return protocolBytesToHex((result as Success).value as List<int>);
  }
}

final class _ResolutionFailure implements Exception {
  const _ResolutionFailure(this.failure);

  final Failure failure;
}
