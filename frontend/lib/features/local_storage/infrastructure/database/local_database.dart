// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

part 'local_database.g.dart';

abstract class _NamedTable extends Table {
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class AccountSessions extends Table {
  @override
  String get tableName => 'account_session';

  IntColumn get singletonId =>
      integer().withDefault(const Constant(1)).check(singletonId.equals(1))();
  BlobColumn get userIdCiphertext => blob()();
  BlobColumn get deviceIdCiphertext => blob().nullable()();
  IntColumn get scope => integer().check(scope.isBetweenValues(0, 1))();
  BlobColumn get tokenMetadataCiphertext => blob()();
  BlobColumn get serverProfileCiphertext => blob()();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};
}

class SecureSecrets extends _NamedTable {
  @override
  String get tableName => 'secure_secrets';

  TextColumn get secretId => text()();
  IntColumn get kind => integer().check(kind.isBetweenValues(0, 31))();
  BlobColumn get wrappedCiphertextOrOpaqueHandle => blob()();
  IntColumn get formatVersion =>
      integer().check(formatVersion.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {secretId};
}

class AccountIdentities extends Table {
  @override
  String get tableName => 'account_identity';

  IntColumn get singletonId =>
      integer().withDefault(const Constant(1)).check(singletonId.equals(1))();
  BlobColumn get verifiedPublicStateCiphertext => blob()();
  IntColumn get backupVersion => integer()
      .withDefault(const Constant(0))
      .check(backupVersion.isBiggerOrEqualValue(0))();
  IntColumn get recoveryStatus =>
      integer().check(recoveryStatus.isBetweenValues(0, 4))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};
}

class EnrollmentIntents extends Table {
  @override
  String get tableName => 'enrollment_intent';

  TextColumn get userId => text()();
  IntColumn get flow => integer().check(flow.isBetweenValues(0, 1))();
  IntColumn get phase => integer().check(phase.isBetweenValues(0, 17))();
  BlobColumn get fingerprint => blob()();
  BlobColumn get deviceState => blob()();
  TextColumn get deviceId => text().nullable()();
  BlobColumn get identityState => blob().nullable()();
  BlobColumn get backup => blob().nullable()();
  IntColumn get backupVersion => integer()
      .withDefault(const Constant(1))
      .check(backupVersion.isBiggerThanValue(0))();
  IntColumn get identityVersion => integer()
      .withDefault(const Constant(1))
      .check(identityVersion.isBiggerThanValue(0))();
  IntColumn get expectedSequence => integer().nullable().check(
    expectedSequence.isNull() | expectedSequence.isBiggerOrEqualValue(0),
  )();
  BlobColumn get previousHash => blob().nullable()();
  BlobColumn get pendingLogRecord => blob().nullable()();
  IntColumn get message => integer().nullable().check(
    message.isNull() | message.isBetweenValues(0, 14),
  )();
  BoolColumn get recoverySecretDisplayed =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get recoveryConfirmed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class Users extends Table {
  @override
  String get tableName => 'users';

  TextColumn get userId => text()();
  BoolColumn get activated => boolean()();
  BlobColumn get directoryEntryCiphertext => blob()();
  IntColumn get localState =>
      integer().check(localState.isBetweenValues(0, 7))();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class Profiles extends Table {
  @override
  String get tableName => 'profiles';

  TextColumn get userId =>
      text().references(Users, #userId, onDelete: KeyAction.cascade)();
  BlobColumn get profileCiphertext => blob()();
  IntColumn get version => integer().check(version.isBiggerOrEqualValue(0))();
  IntColumn get verificationState =>
      integer().check(verificationState.isBetweenValues(0, 4))();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class Devices extends Table {
  @override
  String get tableName => 'devices';

  TextColumn get deviceId => text()();
  TextColumn get userId =>
      text().references(Users, #userId, onDelete: KeyAction.cascade)();
  BlobColumn get publicBundle => blob()();
  BlobColumn get etagCiphertext => blob().nullable()();
  BlobColumn get labelCiphertext => blob().nullable()();
  IntColumn get revocationState =>
      integer().check(revocationState.isBetweenValues(0, 3))();
  IntColumn get bundleVersion => integer().nullable().check(
    bundleVersion.isNull() | bundleVersion.isBiggerThanValue(0),
  )();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

class DeviceLogRecords extends Table {
  @override
  String get tableName => 'device_log';

  TextColumn get userId =>
      text().references(Users, #userId, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer().check(sequence.isBiggerOrEqualValue(0))();
  BlobColumn get signedOpaqueRecord => blob()();
  BlobColumn get recordHash => blob()();
  IntColumn get forkState => integer().check(forkState.isBetweenValues(0, 2))();
  IntColumn get gossipState =>
      integer().check(gossipState.isBetweenValues(0, 3))();

  @override
  Set<Column<Object>> get primaryKey => {userId, sequence};
}

class PairwiseSessions extends Table {
  @override
  String get tableName => 'pairwise_sessions';

  TextColumn get localDeviceId => text()();
  TextColumn get remoteDeviceId => text()();
  BlobColumn get opaqueCryptoStateHandle => blob()();
  IntColumn get stateVersion =>
      integer().check(stateVersion.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {localDeviceId, remoteDeviceId};
}

class Prekeys extends Table {
  @override
  String get tableName => 'prekeys';

  IntColumn get kind => integer().check(kind.isBetweenValues(0, 5))();
  IntColumn get keyId => integer().check(keyId.isBiggerOrEqualValue(0))();
  BlobColumn get privateStateHandle => blob()();
  IntColumn get uploadState =>
      integer().check(uploadState.isBetweenValues(0, 4))();
  IntColumn get useState => integer().check(useState.isBetweenValues(0, 4))();

  @override
  Set<Column<Object>> get primaryKey => {kind, keyId};
}

class MlsGroups extends Table {
  @override
  String get tableName => 'mls_groups';

  TextColumn get groupId => text()();
  BlobColumn get opaqueCryptoStateHandle => blob()();
  IntColumn get acceptedEpoch =>
      integer().check(acceptedEpoch.isBiggerOrEqualValue(0))();
  IntColumn get stateVersion =>
      integer().check(stateVersion.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {groupId};
}

class Conversations extends Table {
  @override
  String get tableName => 'conversations';

  TextColumn get conversationId => text()();
  IntColumn get kind => integer().check(kind.isBetweenValues(0, 2))();
  BlobColumn get listProjectionCiphertext => blob()();
  IntColumn get sortKey => integer()();
  BoolColumn get tombstoned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {conversationId};
}

class Memberships extends Table {
  @override
  String get tableName => 'memberships';

  TextColumn get conversationId => text().references(
    Conversations,
    #conversationId,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get userId =>
      text().references(Users, #userId, onDelete: KeyAction.cascade)();
  BlobColumn get rolePolicyProjectionCiphertext => blob()();

  @override
  Set<Column<Object>> get primaryKey => {conversationId, userId};
}

class Messages extends Table {
  @override
  String get tableName => 'messages';

  TextColumn get messageId => text()();
  TextColumn get conversationId => text().references(
    Conversations,
    #conversationId,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get currentEventId => text()();
  BlobColumn get projectionCiphertext => blob()();
  IntColumn get status => integer().check(status.isBetweenValues(0, 8))();
  IntColumn get revision => integer().check(revision.isBiggerOrEqualValue(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {messageId};
}

class MessageEvents extends Table {
  @override
  String get tableName => 'message_events';

  TextColumn get eventId => text()();
  TextColumn get messageId => text()();
  TextColumn get conversationId => text().references(
    Conversations,
    #conversationId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get eventKind =>
      integer().check(eventKind.isBetweenValues(0, 31))();
  BlobColumn get authenticatedCiphertext => blob()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

class Attachments extends Table {
  @override
  String get tableName => 'attachments';

  TextColumn get attachmentId => text()();
  TextColumn get messageId =>
      text().references(Messages, #messageId, onDelete: KeyAction.cascade)();
  BlobColumn get encryptedDescriptor => blob()();
  IntColumn get transferState =>
      integer().check(transferState.isBetweenValues(0, 8))();
  BlobColumn get boundedCacheHandleCiphertext => blob().nullable()();
  DateTimeColumn get cacheExpiresAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {attachmentId};
}

class InboxEnvelopes extends Table {
  @override
  String get tableName => 'inbox_envelopes';

  TextColumn get envelopeId => text()();
  IntColumn get sequence =>
      integer().unique().check(sequence.isBiggerThanValue(0))();
  BlobColumn get envelopeCiphertext => blob()();
  IntColumn get processingState =>
      integer().check(processingState.isBetweenValues(0, 5))();
  BoolColumn get readyToAcknowledge =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {envelopeId};
}

class OutboxOperations extends Table {
  @override
  String get tableName => 'outbox_operations';

  TextColumn get operationId => text()();
  TextColumn get eventId => text()();
  TextColumn get recipientDeviceId => text()();
  IntColumn get batchIndex =>
      integer().check(batchIndex.isBiggerOrEqualValue(0))();
  BlobColumn get exactRecipientCiphertext => blob()();
  IntColumn get attemptState =>
      integer().check(attemptState.isBetweenValues(0, 6))();
  IntColumn get attemptCount => integer()
      .withDefault(const Constant(0))
      .check(attemptCount.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {operationId, recipientDeviceId};
}

class Receipts extends Table {
  @override
  String get tableName => 'receipts';

  TextColumn get messageId =>
      text().references(Messages, #messageId, onDelete: KeyAction.cascade)();
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  IntColumn get receiptState =>
      integer().check(receiptState.isBetweenValues(0, 2))();
  BlobColumn get projectionCiphertext => blob()();

  @override
  Set<Column<Object>> get primaryKey => {messageId, userId, deviceId};
}

class VoiceRooms extends Table {
  @override
  String get tableName => 'voice_rooms';

  TextColumn get localRoomId => text()();
  BlobColumn get capabilityCiphertext => blob()();
  BlobColumn get metadataCiphertext => blob()();
  IntColumn get liveState => integer().check(liveState.isBetweenValues(0, 4))();

  @override
  Set<Column<Object>> get primaryKey => {localRoomId};
}

class HistoryTransfers extends Table {
  @override
  String get tableName => 'history_transfers';

  TextColumn get transferId => text()();
  BlobColumn get manifestCiphertext => blob()();
  IntColumn get eventProgress => integer()
      .withDefault(const Constant(0))
      .check(eventProgress.isBiggerOrEqualValue(0))();
  IntColumn get sourceCompleteness =>
      integer().check(sourceCompleteness.isBetweenValues(0, 2))();

  @override
  Set<Column<Object>> get primaryKey => {transferId};
}

class SyncCheckpoints extends Table {
  @override
  String get tableName => 'sync_checkpoint';

  IntColumn get singletonId =>
      integer().withDefault(const Constant(1)).check(singletonId.equals(1))();
  IntColumn get highestContiguousAckedSequence => integer()
      .withDefault(const Constant(0))
      .check(highestContiguousAckedSequence.isBiggerOrEqualValue(0))();
  IntColumn get prunedThrough => integer()
      .withDefault(const Constant(0))
      .check(prunedThrough.isBiggerOrEqualValue(0))();
  BlobColumn get etagsCiphertext => blob()();
  IntColumn get retryState =>
      integer().check(retryState.isBetweenValues(0, 5))();
  IntColumn get protocolVersion =>
      integer().check(protocolVersion.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};
}

class LocalPreferences extends Table {
  @override
  String get tableName => 'local_preferences';

  TextColumn get preferenceKey => text()();
  BlobColumn get valueCiphertext => blob()();
  IntColumn get valueVersion =>
      integer().check(valueVersion.isBiggerThanValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {preferenceKey};
}

class QuarantineRecords extends Table {
  @override
  String get tableName => 'quarantine';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get reasonCode =>
      integer().check(reasonCode.isBetweenValues(0, 63))();
  BlobColumn get opaqueDigest => blob()();
  DateTimeColumn get receivedAt => dateTime().withDefault(currentDateAndTime)();
}

class StorageMigrationHooks {
  const StorageMigrationHooks();

  Future<void> beforeUpgrade(int from, int to) async {}

  Future<void> afterUpgrade(int from, int to) async {}
}

@DriftDatabase(
  tables: [
    AccountSessions,
    SecureSecrets,
    AccountIdentities,
    EnrollmentIntents,
    Users,
    Profiles,
    Devices,
    DeviceLogRecords,
    PairwiseSessions,
    Prekeys,
    MlsGroups,
    Conversations,
    Memberships,
    Messages,
    MessageEvents,
    Attachments,
    InboxEnvelopes,
    OutboxOperations,
    Receipts,
    VoiceRooms,
    HistoryTransfers,
    SyncCheckpoints,
    LocalPreferences,
    QuarantineRecords,
  ],
)
final class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor, {StorageMigrationHooks? migrationHooks})
    : _migrationHooks = migrationHooks ?? const StorageMigrationHooks();

  static const currentSchemaVersion = 2;
  final StorageMigrationHooks _migrationHooks;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await transaction(() async {
        await _migrationHooks.beforeUpgrade(0, schemaVersion);
        await migrator.createAll();
        await _migrationHooks.afterUpgrade(0, schemaVersion);
      });
    },
    onUpgrade: (migrator, from, to) async {
      await transaction(() async {
        await _migrationHooks.beforeUpgrade(from, to);
        if (from < 1) {
          await migrator.createAll();
        } else if (from < 2) {
          await migrator.createTable(enrollmentIntents);
        }
        await _migrationHooks.afterUpgrade(from, to);
      });
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (!details.wasCreated) {
        final integrityRows = await customSelect('PRAGMA quick_check').get();
        final isValid =
            integrityRows.length == 1 &&
            integrityRows.single.data.values.singleOrNull == 'ok';
        if (!isValid) {
          throw const LocalDatabaseIntegrityException();
        }
      }
    },
  );

  Future<T> writeTransaction<T>(Future<T> Function() operation) {
    return transaction(operation);
  }

  Stream<List<Conversation>> watchConversationRows() {
    final query = select(conversations)
      ..where((row) => row.tombstoned.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.sortKey)]);
    return query.watch();
  }

  Future<CleanupReportRow> cleanupBounded({required int maximumEntries}) async {
    if (maximumEntries <= 0) {
      return const CleanupReportRow(removedEntries: 0, hasMore: true);
    }
    return transaction(() async {
      final expired =
          await (select(attachments)
                ..where(
                  (row) =>
                      row.cacheExpiresAt.isSmallerOrEqualValue(DateTime.now()),
                )
                ..limit(maximumEntries))
              .get();
      for (final row in expired) {
        await (update(
          attachments,
        )..where((item) => item.attachmentId.equals(row.attachmentId))).write(
          const AttachmentsCompanion(
            boundedCacheHandleCiphertext: Value(null),
            cacheExpiresAt: Value(null),
          ),
        );
      }

      final remainingBudget = maximumEntries - expired.length;
      var removedQuarantine = 0;
      if (remainingBudget > 0) {
        final overflow =
            await (select(quarantineRecords)
                  ..orderBy([(row) => OrderingTerm.desc(row.receivedAt)])
                  ..limit(remainingBudget, offset: 256))
                .get();
        for (final row in overflow) {
          removedQuarantine += await (delete(
            quarantineRecords,
          )..where((item) => item.id.equals(row.id))).go();
        }
      }
      final remaining = await (selectOnly(
        quarantineRecords,
      )..addColumns([quarantineRecords.id.count()])).getSingle();
      final remainingCount = remaining.read(quarantineRecords.id.count()) ?? 0;
      return CleanupReportRow(
        removedEntries: expired.length + removedQuarantine,
        hasMore: remainingCount > 256 || expired.length == maximumEntries,
      );
    });
  }
}

final class LocalDatabaseIntegrityException implements Exception {
  const LocalDatabaseIntegrityException();
}

final class CleanupReportRow {
  const CleanupReportRow({required this.removedEntries, required this.hasMore});

  final int removedEntries;
  final bool hasMore;
}
