import 'dart:convert';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/drift_repository_base.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:drift/drift.dart';

final class DriftGroupRepository extends DriftRepositoryBase
    implements GroupRepositoryPort {
  const DriftGroupRepository(super.database);

  @override
  Stream<GroupState?> watchGroup(String groupId) {
    final query = database.select(database.mlsGroups)
      ..where((row) => row.groupId.equals(groupId));
    return query.watchSingleOrNull().map((row) {
      if (row == null || row.controlProjectionCiphertext == null) return null;
      return _overlayQueueGap(
        _decodeState(row.controlProjectionCiphertext!),
        row.queueGapRecoveryState,
      );
    });
  }

  @override
  Stream<List<GroupMessage>> watchMessages(String groupId) {
    final query = database.select(database.messages)
      ..where((row) => row.conversationId.equals(groupId))
      ..orderBy([
        (row) => OrderingTerm.asc(row.orderingMs),
        (row) => OrderingTerm.asc(row.orderingEventId),
      ]);
    return query.watch().map(
      (rows) => List.unmodifiable(
        rows
            .where((row) => !row.deletedForMe)
            .map(
              (row) => GroupMessage(
                messageId: row.messageId,
                groupId: row.conversationId,
                senderUserId: row.senderUserId,
                text: row.deletedForEveryone
                    ? ''
                    : utf8.decode(
                        row.projectionCiphertext,
                        allowMalformed: false,
                      ),
                createdMs: row.createdAt.millisecondsSinceEpoch,
                localPreviewOnly:
                    row.status == MessageTransportState.localOnly.index,
              ),
            ),
      ),
    );
  }

  @override
  Future<Result<GroupState?>> readGroup(String groupId) async {
    try {
      final row = await (database.select(
        database.mlsGroups,
      )..where((item) => item.groupId.equals(groupId))).getSingleOrNull();
      if (row == null || row.controlProjectionCiphertext == null) {
        return const Result.success(null);
      }
      return Result.success(
        _overlayQueueGap(
          _decodeState(row.controlProjectionCiphertext!),
          row.queueGapRecoveryState,
        ),
      );
    } on FormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<Uint8List?>> readOpaqueMlsState(String groupId) async {
    try {
      final row = await (database.select(
        database.mlsGroups,
      )..where((item) => item.groupId.equals(groupId))).getSingleOrNull();
      return Result.success(row?.opaqueCryptoStateHandle);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> commitTransition({
    required GroupState? expectedPrevious,
    required GroupState next,
    required PreparedGroupTransition prepared,
    required bool developmentPreviewOnly,
  }) => _runGroupWrite(() async {
    final event = prepared.signedControl.event;
    if (event.groupId != next.groupId ||
        prepared.signedControl.controlStateHash != next.controlStateHash ||
        event.revision != next.controlRevision) {
      throw const _GroupIntegrityFailure();
    }

    if (expectedPrevious == null) {
      final existing = await (database.select(
        database.mlsGroups,
      )..where((row) => row.groupId.equals(next.groupId))).getSingleOrNull();
      if (existing != null) throw const _GroupConflict();
      await database
          .into(database.conversations)
          .insert(
            ConversationsCompanion.insert(
              conversationId: next.groupId,
              kind: ConversationKind.group.index,
              listProjectionCiphertext: Uint8List(0),
              sortKey: event.createdMs,
              displayTitleCiphertext: Value(
                Uint8List.fromList(utf8.encode(next.metadata.name)),
              ),
            ),
          );
      await database
          .into(database.mlsGroups)
          .insert(
            MlsGroupsCompanion.insert(
              groupId: next.groupId,
              opaqueCryptoStateHandle: prepared.newOpaqueMlsState,
              acceptedEpoch: next.acceptedEpoch,
              stateVersion: 1,
              controlProjectionCiphertext: Value(_encodeState(next)),
              controlRevision: Value(next.controlRevision),
              controlStateHash: Value(_hexBytes(next.controlStateHash)),
              lifecycle: Value(next.lifecycle.index),
            ),
          );
    } else {
      final previousHash = _hexBytes(expectedPrevious.controlStateHash);
      final current =
          await (database.select(database.mlsGroups)..where(
                (row) =>
                    row.groupId.equals(next.groupId) &
                    row.controlRevision.equals(
                      expectedPrevious.controlRevision,
                    ),
              ))
              .getSingleOrNull();
      if (current == null ||
          !_bytesEqual(current.controlStateHash, previousHash)) {
        throw const _GroupConflict();
      }
      final updated =
          await (database.update(database.mlsGroups)..where(
                (row) =>
                    row.groupId.equals(next.groupId) &
                    row.controlRevision.equals(
                      expectedPrevious.controlRevision,
                    ),
              ))
              .write(
                MlsGroupsCompanion(
                  opaqueCryptoStateHandle: Value(prepared.newOpaqueMlsState),
                  acceptedEpoch: Value(next.acceptedEpoch),
                  stateVersion: Value(current.stateVersion + 1),
                  controlProjectionCiphertext: Value(_encodeState(next)),
                  controlRevision: Value(next.controlRevision),
                  controlStateHash: Value(_hexBytes(next.controlStateHash)),
                  lifecycle: Value(next.lifecycle.index),
                  pendingMutationId: const Value(null),
                ),
              );
      if (updated != 1) throw const _GroupConflict();
      await (database.update(
        database.conversations,
      )..where((row) => row.conversationId.equals(next.groupId))).write(
        ConversationsCompanion(
          displayTitleCiphertext: Value(
            Uint8List.fromList(utf8.encode(next.metadata.name)),
          ),
          sortKey: Value(event.createdMs),
        ),
      );
      await (database.delete(
        database.memberships,
      )..where((row) => row.conversationId.equals(next.groupId))).go();
    }

    for (final member in next.members) {
      await database
          .into(database.memberships)
          .insert(
            MembershipsCompanion.insert(
              conversationId: next.groupId,
              userId: member.userId,
              rolePolicyProjectionCiphertext: _encodeMember(member),
            ),
          );
    }
    await database
        .into(database.groupControlEvents)
        .insert(
          GroupControlEventsCompanion.insert(
            eventId: event.eventId,
            groupId: event.groupId,
            revision: event.revision,
            previousControlStateHash: Value(
              event.previousControlStateHash == null
                  ? null
                  : _hexBytes(event.previousControlStateHash!),
            ),
            controlStateHash: _hexBytes(next.controlStateHash),
            mlsCommitHash: Value(
              event.mlsCommitHash == null
                  ? null
                  : _hexBytes(event.mlsCommitHash!),
            ),
            epoch: event.mlsEpoch,
            signerUserId: event.signerUserId,
            signerDeviceId: event.signerDeviceId,
            operationKind: event.operation.code,
            canonicalControl: prepared.signedControl.canonicalBytes,
            signature: prepared.signedControl.signature,
            applyState: 0,
            createdMs: event.createdMs,
          ),
        );
    if (prepared.outbound) {
      await database
          .into(database.groupOutboundObjects)
          .insert(
            GroupOutboundObjectsCompanion.insert(
              operationId: prepared.mutationId,
              groupId: next.groupId,
              eventId: event.eventId,
              epoch: next.acceptedEpoch,
              mlsObject: prepared.mlsObject,
              deliveryState: developmentPreviewOnly ? 0 : 1,
            ),
          );
    }
  });

  @override
  Future<Result<void>> commitMessage({
    required GroupState expectedGroup,
    required PreparedGroupMessage prepared,
    required bool developmentPreviewOnly,
  }) => _runGroupWrite(() async {
    if (prepared.groupId != expectedGroup.groupId ||
        prepared.epoch != expectedGroup.acceptedEpoch) {
      throw const _GroupIntegrityFailure();
    }
    final hash = _hexBytes(expectedGroup.controlStateHash);
    final row =
        await (database.select(database.mlsGroups)..where(
              (item) =>
                  item.groupId.equals(expectedGroup.groupId) &
                  item.controlRevision.equals(expectedGroup.controlRevision),
            ))
            .getSingleOrNull();
    if (row == null ||
        !_bytesEqual(row.controlStateHash, hash) ||
        row.queueGapRecoveryState != 0) {
      throw const _GroupConflict();
    }
    final updated =
        await (database.update(database.mlsGroups)..where(
              (item) =>
                  item.groupId.equals(expectedGroup.groupId) &
                  item.controlRevision.equals(expectedGroup.controlRevision),
            ))
            .write(
              MlsGroupsCompanion(
                opaqueCryptoStateHandle: Value(prepared.newOpaqueMlsState),
                stateVersion: Value(row.stateVersion + 1),
              ),
            );
    if (updated != 1) throw const _GroupConflict();
    await database
        .into(database.messages)
        .insert(
          MessagesCompanion.insert(
            messageId: prepared.messageId,
            conversationId: prepared.groupId,
            currentEventId: prepared.messageId,
            projectionCiphertext: Uint8List.fromList(
              utf8.encode(prepared.text),
            ),
            status: developmentPreviewOnly
                ? MessageTransportState.localOnly.index
                : MessageTransportState.queued.index,
            revision: 0,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              prepared.createdMs,
              isUtc: true,
            ),
            senderUserId: Value(prepared.senderUserId),
            senderDeviceId: Value(prepared.senderDeviceId),
            orderingMs: Value(prepared.createdMs),
            orderingEventId: Value(prepared.messageId),
          ),
        );
    await database
        .into(database.messageEvents)
        .insert(
          MessageEventsCompanion.insert(
            eventId: prepared.messageId,
            messageId: prepared.messageId,
            conversationId: prepared.groupId,
            eventKind: 0,
            authenticatedCiphertext: prepared.mlsObject,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              prepared.createdMs,
              isUtc: true,
            ),
          ),
        );
    await database
        .into(database.groupOutboundObjects)
        .insert(
          GroupOutboundObjectsCompanion.insert(
            operationId: prepared.operationId,
            groupId: prepared.groupId,
            eventId: prepared.messageId,
            epoch: prepared.epoch,
            mlsObject: prepared.mlsObject,
            deliveryState: developmentPreviewOnly ? 0 : 1,
          ),
        );
    await (database.update(
      database.conversations,
    )..where((row) => row.conversationId.equals(prepared.groupId))).write(
      ConversationsCompanion(
        listProjectionCiphertext: Value(
          Uint8List.fromList(utf8.encode(prepared.text)),
        ),
        sortKey: Value(prepared.createdMs),
        lastActivityEventId: Value(prepared.messageId),
      ),
    );
  });

  @override
  Future<Result<void>> quarantine(GroupQuarantineRecord record) =>
      _runGroupWrite(() async {
        final row =
            await (database.select(database.mlsGroups)
                  ..where((item) => item.groupId.equals(record.groupId)))
                .getSingleOrNull();
        if (row == null || row.controlProjectionCiphertext == null) {
          throw const _GroupIntegrityFailure();
        }
        final state = _decodeState(row.controlProjectionCiphertext!);
        final lifecycle = record.reason == GroupQuarantineReason.siblingCommit
            ? GroupLifecycle.forkQuarantined
            : GroupLifecycle.controlQuarantined;
        final quarantined = state.copyWith(
          lifecycle: lifecycle,
          quarantineReason: record.reason,
        );
        await (database.update(
          database.mlsGroups,
        )..where((item) => item.groupId.equals(record.groupId))).write(
          MlsGroupsCompanion(
            controlProjectionCiphertext: Value(_encodeState(quarantined)),
            lifecycle: Value(lifecycle.index),
          ),
        );
        await database
            .into(database.quarantineRecords)
            .insert(
              QuarantineRecordsCompanion.insert(
                reasonCode: 32 + record.reason.index,
                opaqueDigest: record.opaqueDigest,
                receivedAt: Value(record.receivedAt.toUtc()),
              ),
            );
      });

  Future<Result<void>> _runGroupWrite(Future<void> Function() operation) async {
    try {
      await database.writeTransaction(operation);
      return const Result.success(null);
    } on _GroupConflict {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.conflict),
      );
    } on _GroupIntegrityFailure {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  GroupState _overlayQueueGap(GroupState state, int queueGapState) {
    if (queueGapState == 0 ||
        state.lifecycle == GroupLifecycle.removed ||
        state.lifecycle == GroupLifecycle.left) {
      return state;
    }
    return state.copyWith(
      lifecycle: GroupLifecycle.queueGapRejoinRequired,
      clearQuarantineReason: true,
    );
  }
}

Uint8List _encodeState(GroupState state) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'group_id': state.groupId,
      'metadata': {
        'name': state.metadata.name,
        'description': state.metadata.description,
        'photo': state.metadata.photoCapability,
      },
      'invite': state.invitationPolicy.index,
      'history': state.historySharingPolicy.index,
      'members': [for (final member in state.members) _memberJson(member)],
      'revision': state.controlRevision,
      'hash': state.controlStateHash,
      'epoch': state.acceptedEpoch,
      'lifecycle': state.lifecycle.index,
      'quarantine': state.quarantineReason?.index,
    }),
  ),
);

GroupState _decodeState(Uint8List bytes) {
  final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
  if (value is! Map<String, Object?>) {
    throw const FormatException('invalid group projection');
  }
  final metadata = value['metadata'];
  final members = value['members'];
  if (metadata is! Map<String, Object?> || members is! List<Object?>) {
    throw const FormatException('invalid group projection');
  }
  final quarantine = value['quarantine'] as int?;
  return GroupState(
    groupId: value['group_id']! as String,
    metadata: GroupMetadata(
      name: metadata['name']! as String,
      description: metadata['description']! as String,
      photoCapability: metadata['photo'] as String?,
    ),
    invitationPolicy: GroupInvitationPolicy.values[value['invite']! as int],
    historySharingPolicy:
        GroupHistorySharingPolicy.values[value['history']! as int],
    members: [for (final member in members) _decodeMember(member!)],
    controlRevision: value['revision']! as int,
    controlStateHash: value['hash']! as String,
    acceptedEpoch: value['epoch']! as int,
    lifecycle: GroupLifecycle.values[value['lifecycle']! as int],
    quarantineReason: quarantine == null
        ? null
        : GroupQuarantineReason.values[quarantine],
  );
}

Map<String, Object?> _memberJson(GroupMember member) => {
  'user_id': member.userId,
  'name': member.displayName,
  'role': member.role.index,
  'membership': member.membership.index,
  'verified': member.verified,
  'devices': member.deviceIds,
};

Uint8List _encodeMember(GroupMember member) =>
    Uint8List.fromList(utf8.encode(jsonEncode(_memberJson(member))));

GroupMember _decodeMember(Object value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('invalid member projection');
  }
  return GroupMember(
    userId: value['user_id']! as String,
    displayName: value['name']! as String,
    role: GroupRole.values[value['role']! as int],
    membership: GroupMembershipState.values[value['membership']! as int],
    verified: value['verified']! as bool,
    deviceIds: (value['devices']! as List<Object?>).cast<String>(),
  );
}

Uint8List _hexBytes(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
    throw const FormatException('invalid hexadecimal value');
  }
  return Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
}

bool _bytesEqual(Uint8List? left, Uint8List right) {
  if (left == null || left.length != right.length) return false;
  for (var index = 0; index < right.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _GroupConflict implements Exception {
  const _GroupConflict();
}

final class _GroupIntegrityFailure implements Exception {
  const _GroupIntegrityFailure();
}
