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
  IntColumn get stateRevision => integer()
      .withDefault(const Constant(1))
      .check(stateRevision.isBiggerThanValue(0))();

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
  TextColumn get decryptedLabel => text().nullable()();
  IntColumn get revocationState =>
      integer().check(revocationState.isBetweenValues(0, 3))();
  IntColumn get bundleVersion => integer().nullable().check(
    bundleVersion.isNull() | bundleVersion.isBiggerThanValue(0),
  )();
  IntColumn get lastSignedPrekeyRotationUnixDay => integer()
      .withDefault(const Constant(0))
      .check(lastSignedPrekeyRotationUnixDay.isBiggerOrEqualValue(0))();
  TextColumn get createdDate => text().nullable()();
  TextColumn get lastActiveDate => text().nullable()();
  BoolColumn get isCurrentDevice =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get ownerListing => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

/// Exact own-account log append retained before its non-idempotent POST.
class DeviceLogMutations extends Table {
  @override
  String get tableName => 'device_log_mutations';

  TextColumn get operationId => text()();
  TextColumn get userId => text()();
  IntColumn get mutationKind =>
      integer().check(mutationKind.isBetweenValues(0, 3))();
  TextColumn get targetDeviceId => text().nullable()();
  IntColumn get expectedSequence =>
      integer().check(expectedSequence.isBiggerOrEqualValue(0))();
  BlobColumn get previousHeadHash => blob()();
  BlobColumn get exactRecord => blob()();
  IntColumn get state => integer().check(state.isBetweenValues(0, 3))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class SecurityPostures extends Table {
  @override
  String get tableName => 'security_posture';

  IntColumn get singletonId =>
      integer().withDefault(const Constant(1)).check(singletonId.equals(1))();
  // 0 normal, 1 globally-forked, 2 pending authenticated device change.
  IntColumn get state => integer().check(state.isBetweenValues(0, 2))();
  IntColumn get evidenceKind => integer().nullable().check(
    evidenceKind.isNull() | evidenceKind.isBetweenValues(0, 4),
  )();
  DateTimeColumn get detectedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singletonId};
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
  TextColumn get remoteUserId => text().withDefault(const Constant(''))();
  TextColumn get remoteDeviceId => text()();
  BlobColumn get sessionId => blob().nullable()();
  BlobColumn get opaqueCryptoStateHandle => blob()();
  IntColumn get stateVersion =>
      integer().check(stateVersion.isBiggerThanValue(0))();
  IntColumn get skippedKeyCount => integer()
      .withDefault(const Constant(0))
      .check(skippedKeyCount.isBetweenValues(0, 2000))();
  IntColumn get disposition => integer()
      .withDefault(const Constant(0))
      .check(disposition.isBetweenValues(0, 1))();
  IntColumn get repairState => integer()
      .withDefault(const Constant(0))
      .check(repairState.isBetweenValues(0, 3))();
  BlobColumn get repairAuthorization => blob().nullable()();
  DateTimeColumn get lastAuthenticatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {localDeviceId, remoteDeviceId};
}

/// The single receive-only session retained during simultaneous initiation.
class PairwiseSessionAlternates extends Table {
  @override
  String get tableName => 'pairwise_session_alternates';

  BlobColumn get sessionId => blob()();
  TextColumn get localDeviceId => text()();
  TextColumn get remoteUserId => text()();
  TextColumn get remoteDeviceId => text()();
  BlobColumn get opaqueCryptoStateHandle => blob()();
  IntColumn get stateVersion =>
      integer().check(stateVersion.isBiggerThanValue(0))();
  IntColumn get skippedKeyCount =>
      integer().check(skippedKeyCount.isBetweenValues(0, 2000))();
  IntColumn get repairState =>
      integer().check(repairState.isBetweenValues(0, 3))();
  BlobColumn get repairAuthorization => blob().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAuthenticatedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {localDeviceId, remoteDeviceId},
  ];
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

/// Resumable public/checkpoint projection for an authenticated native prekey plan.
@DataClassName('StoredPrekeyMaintenancePlan')
class PrekeyMaintenancePlans extends Table {
  @override
  String get tableName => 'prekey_maintenance_plans';

  TextColumn get deviceId => text()();
  IntColumn get stage => integer().check(stage.isBetweenValues(0, 2))();
  IntColumn get expectedStateRevision =>
      integer().check(expectedStateRevision.isBiggerThanValue(0))();
  IntColumn get preparedUnixDay =>
      integer().check(preparedUnixDay.isBiggerOrEqualValue(0))();
  IntColumn get bundleVersion =>
      integer().check(bundleVersion.isBiggerThanValue(0))();
  IntColumn get currentSignedPrekeyCreatedUnixDay => integer().check(
    currentSignedPrekeyCreatedUnixDay.isBiggerOrEqualValue(0),
  )();
  BlobColumn get batchId => blob()();
  BlobColumn get nativeUploadProjection => blob()();
  BlobColumn get exactLogRecord => blob().nullable()();
  IntColumn get expectedLogSequence => integer().nullable().check(
    expectedLogSequence.isNull() | expectedLogSequence.isBiggerOrEqualValue(0),
  )();
  BlobColumn get previousLogHead => blob().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
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
  IntColumn get queueGapRecoveryState => integer()
      .withDefault(const Constant(0))
      .check(queueGapRecoveryState.isBetweenValues(0, 2))();
  BlobColumn get controlProjectionCiphertext => blob().nullable()();
  IntColumn get controlRevision => integer()
      .withDefault(const Constant(0))
      .check(controlRevision.isBiggerOrEqualValue(0))();
  BlobColumn get controlStateHash => blob().nullable()();
  IntColumn get lifecycle => integer()
      .withDefault(const Constant(0))
      .check(lifecycle.isBetweenValues(0, 6))();
  TextColumn get pendingMutationId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {groupId};
}

@DataClassName('StoredGroupControlEventRow')
class GroupControlEvents extends Table {
  @override
  String get tableName => 'group_control_events';

  TextColumn get eventId => text()();
  TextColumn get groupId =>
      text().references(MlsGroups, #groupId, onDelete: KeyAction.cascade)();
  IntColumn get revision => integer().check(revision.isBiggerThanValue(0))();
  BlobColumn get previousControlStateHash => blob().nullable()();
  BlobColumn get controlStateHash => blob()();
  BlobColumn get mlsCommitHash => blob().nullable()();
  IntColumn get epoch => integer().check(epoch.isBiggerOrEqualValue(0))();
  TextColumn get signerUserId => text()();
  TextColumn get signerDeviceId => text()();
  IntColumn get operationKind =>
      integer().check(operationKind.isBetweenValues(1, 8))();
  BlobColumn get canonicalControl => blob()();
  BlobColumn get signature => blob()();
  IntColumn get applyState =>
      integer().check(applyState.isBetweenValues(0, 2))();
  IntColumn get createdMs =>
      integer().check(createdMs.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {eventId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {groupId, revision},
  ];
}

@DataClassName('StoredGroupOutboundObjectRow')
class GroupOutboundObjects extends Table {
  @override
  String get tableName => 'group_outbound_objects';

  TextColumn get operationId => text()();
  TextColumn get groupId =>
      text().references(MlsGroups, #groupId, onDelete: KeyAction.cascade)();
  TextColumn get eventId => text()();
  IntColumn get epoch => integer().check(epoch.isBiggerOrEqualValue(0))();
  BlobColumn get mlsObject => blob()();
  // 0 development preview only, 1 blocked by production gate, 2 ready for piece 19.
  IntColumn get deliveryState =>
      integer().check(deliveryState.isBetweenValues(0, 2))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class Conversations extends Table {
  @override
  String get tableName => 'conversations';

  TextColumn get conversationId => text()();
  IntColumn get kind => integer().check(kind.isBetweenValues(0, 2))();
  BlobColumn get listProjectionCiphertext => blob()();
  IntColumn get sortKey => integer()();
  BoolColumn get tombstoned => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get peerUserId => text().nullable()();
  TextColumn get lastActivityEventId => text().nullable()();
  IntColumn get unreadCount => integer()
      .withDefault(const Constant(0))
      .check(unreadCount.isBiggerOrEqualValue(0))();
  DateTimeColumn get mutedUntil => dateTime().nullable()();
  BlobColumn get draftCiphertext => blob().nullable()();
  BlobColumn get displayTitleCiphertext => blob().nullable()();

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
  TextColumn get senderUserId => text().withDefault(const Constant(''))();
  TextColumn get senderDeviceId => text().withDefault(const Constant(''))();
  TextColumn get replyToMessageId => text().nullable()();
  BlobColumn get quoteFallbackCiphertext => blob().nullable()();
  IntColumn get orderingMs => integer().withDefault(const Constant(0))();
  TextColumn get orderingEventId => text().withDefault(const Constant(''))();
  IntColumn get timestampState => integer()
      .withDefault(const Constant(0))
      .check(timestampState.isBetweenValues(0, 1))();
  BoolColumn get deletedForEveryone =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get deletedForMe => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get starred => boolean().withDefault(const Constant(false))();
  BoolColumn get unread => boolean().withDefault(const Constant(false))();

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

/// Every authenticated version-1 event fact retained for deterministic rebuilds.
class StoredApplicationEvents extends Table {
  @override
  String get tableName => 'application_events';

  TextColumn get eventId => text()();
  TextColumn get conversationId => text()();
  IntColumn get kind => integer().check(kind.isBetweenValues(1, 65535))();
  TextColumn get senderUserId => text()();
  TextColumn get senderDeviceId => text()();
  IntColumn get senderCounter =>
      integer().check(senderCounter.isBiggerThanValue(0))();
  IntColumn get createdMs =>
      integer().check(createdMs.isBiggerOrEqualValue(0))();
  IntColumn get orderingMs => integer()();
  BlobColumn get canonicalEvent => blob()();
  BlobColumn get bodyProjection => blob()();
  IntColumn get applyState =>
      integer().check(applyState.isBetweenValues(0, 5))();
  BoolColumn get localOrigin => boolean().withDefault(const Constant(false))();
  TextColumn get localDeviceId => text().withDefault(const Constant(''))();
  TextColumn get targetMessageId => text().nullable()();
  IntColumn get revision => integer().nullable().check(
    revision.isNull() | revision.isBiggerThanValue(0),
  )();
  DateTimeColumn get authenticatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

/// Unknown future versions/kinds are retained but never projected.
class UnsupportedApplicationEvents extends Table {
  @override
  String get tableName => 'unsupported_application_events';

  TextColumn get recordKey => text()();
  TextColumn get eventId => text().nullable().unique()();
  TextColumn get conversationId => text().nullable()();
  IntColumn get version => integer().check(version.isBetweenValues(0, 255))();
  IntColumn get kind => integer().nullable().check(
    kind.isNull() | kind.isBetweenValues(0, 65535),
  )();
  TextColumn get senderUserId => text()();
  TextColumn get senderDeviceId => text()();
  IntColumn get senderCounter => integer().nullable().check(
    senderCounter.isNull() | senderCounter.isBiggerThanValue(0),
  )();
  IntColumn get applyState => integer()
      .withDefault(const Constant(0))
      .check(applyState.isBetweenValues(0, 2))();
  BlobColumn get retainedPayload => blob()();
  DateTimeColumn get authenticatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {recordKey};
}

class ApplicationSenderCounters extends Table {
  @override
  String get tableName => 'application_sender_counters';

  TextColumn get deviceId => text()();
  IntColumn get lastCounter => integer()
      .withDefault(const Constant(0))
      .check(lastCounter.isBiggerOrEqualValue(0))();

  @override
  Set<Column<Object>> get primaryKey => {deviceId};
}

class MessageReactions extends Table {
  @override
  String get tableName => 'message_reactions';

  TextColumn get messageId =>
      text().references(Messages, #messageId, onDelete: KeyAction.cascade)();
  TextColumn get reactingUserId => text()();
  TextColumn get eventId => text()();
  BlobColumn get emojiCiphertext => blob().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {messageId, reactingUserId};
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
  TextColumn get opaqueEventId => text().nullable()();
  IntColumn get dependencyClass => integer().nullable().check(
    dependencyClass.isNull() | dependencyClass.isBetweenValues(0, 1),
  )();
  IntColumn get attemptCount => integer()
      .withDefault(const Constant(0))
      .check(attemptCount.isBiggerOrEqualValue(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {envelopeId};
}

class OutboxOperations extends Table {
  @override
  String get tableName => 'outbox_operations';

  TextColumn get operationId => text()();
  TextColumn get eventId => text()();
  TextColumn get recipientDeviceId => text()();
  TextColumn get recipientUserId => text().withDefault(const Constant(''))();
  IntColumn get batchIndex =>
      integer().check(batchIndex.isBiggerOrEqualValue(0))();
  BlobColumn get exactRecipientCiphertext => blob()();
  IntColumn get attemptState =>
      integer().check(attemptState.isBetweenValues(0, 6))();
  IntColumn get attemptCount => integer()
      .withDefault(const Constant(0))
      .check(attemptCount.isBiggerOrEqualValue(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get terminalAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId, recipientDeviceId};
}

class InboxEventDeduplications extends Table {
  @override
  String get tableName => 'inbox_event_deduplication';

  TextColumn get opaqueEventId => text()();
  TextColumn get firstEnvelopeId => text()();
  IntColumn get dependencyClass =>
      integer().check(dependencyClass.isBetweenValues(0, 1))();
  DateTimeColumn get committedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {opaqueEventId};
}

/// Cryptographic replay identifiers survive inbox acknowledgement cleanup.
class PairwiseReplayMarkers extends Table {
  @override
  String get tableName => 'pairwise_replay_markers';

  BlobColumn get replayMarker => blob()();
  BlobColumn get sessionId => blob()();
  IntColumn get signedPrekeyId => integer().nullable().check(
    signedPrekeyId.isNull() | signedPrekeyId.isBetweenValues(0, 0x7fffffff),
  )();
  IntColumn get pqSignedPrekeyId => integer().nullable().check(
    pqSignedPrekeyId.isNull() | pqSignedPrekeyId.isBetweenValues(0, 0x7fffffff),
  )();
  TextColumn get firstEnvelopeId => text()();
  DateTimeColumn get committedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {replayMarker};
}

/// Authenticated plaintext remains opaque until message semantics are implemented.
class PairwiseOpenedPayloads extends Table {
  @override
  String get tableName => 'pairwise_opened_payloads';

  TextColumn get envelopeId => text()();
  TextColumn get opaqueEventId => text()();
  TextColumn get senderUserId => text()();
  TextColumn get senderDeviceId => text()();
  BlobColumn get sessionId => blob()();
  BlobColumn get replayMarker => blob()();
  BlobColumn get openedOpaquePayload => blob()();
  BoolColumn get applicationApplied =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get committedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {envelopeId};
}

/// Current-device application marker committed with remote ciphertext targets.
class PairwiseLocalApplications extends Table {
  @override
  String get tableName => 'pairwise_local_applications';

  TextColumn get operationId => text()();
  TextColumn get eventId => text().unique()();
  TextColumn get localDeviceId => text()();
  BlobColumn get openedOpaquePayload => blob()();
  BoolColumn get applicationApplied =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get committedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

/// Tombstones contain no key material and make one-time consumption auditable.
class PairwiseConsumedPrekeys extends Table {
  @override
  String get tableName => 'pairwise_consumed_prekeys';

  TextColumn get localDeviceId => text()();
  IntColumn get algorithm => integer().check(algorithm.isBetweenValues(0, 1))();
  IntColumn get keyId => integer().check(keyId.isBiggerOrEqualValue(0))();
  TextColumn get firstEnvelopeId => text()();
  DateTimeColumn get consumedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {localDeviceId, algorithm, keyId};
}

class StaleDeviceRefreshRequests extends Table {
  @override
  String get tableName => 'stale_device_refresh_requests';

  TextColumn get userId => text()();
  TextColumn get staleDeviceId => text()();
  IntColumn get state => integer()
      .withDefault(const Constant(0))
      .check(state.isBetweenValues(0, 3))();
  IntColumn get attemptCount => integer()
      .withDefault(const Constant(0))
      .check(attemptCount.isBiggerOrEqualValue(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, staleDeviceId};
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

/// Durable work created only after an incoming message projection commits.
class PendingApplicationReceipts extends Table {
  @override
  String get tableName => 'pending_application_receipts';

  TextColumn get messageId =>
      text().references(Messages, #messageId, onDelete: KeyAction.cascade)();
  TextColumn get conversationId => text()();
  TextColumn get targetUserId => text()();
  TextColumn get localDeviceId => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {messageId, localDeviceId};
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
  TextColumn get sourceDeviceId => text().withDefault(const Constant(''))();
  TextColumn get targetDeviceId => text().withDefault(const Constant(''))();
  IntColumn get direction => integer()
      .withDefault(const Constant(0))
      .check(direction.isBetweenValues(0, 1))();
  IntColumn get state => integer()
      .withDefault(const Constant(0))
      .check(state.isBetweenValues(0, 7))();
  IntColumn get nextBatchIndex => integer()
      .withDefault(const Constant(0))
      .check(nextBatchIndex.isBiggerOrEqualValue(0))();
  IntColumn get eventProgress => integer()
      .withDefault(const Constant(0))
      .check(eventProgress.isBiggerOrEqualValue(0))();
  IntColumn get sourceCompleteness =>
      integer().check(sourceCompleteness.isBetweenValues(0, 2))();
  BoolColumn get groupReinviteRequired =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get queueGapRecoveryRequired =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {transferId};
}

class HistoryTransferBatches extends Table {
  @override
  String get tableName => 'history_transfer_batches';

  TextColumn get transferId => text().references(
    HistoryTransfers,
    #transferId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get batchIndex =>
      integer().check(batchIndex.isBiggerOrEqualValue(0))();
  TextColumn get controlEventId => text().unique()();
  IntColumn get eventCount =>
      integer().check(eventCount.isBetweenValues(1, 32))();
  BoolColumn get finalBatch => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {transferId, batchIndex};
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
  IntColumn get queueGapState => integer()
      .withDefault(const Constant(0))
      .check(queueGapState.isBetweenValues(0, 1))();
  BoolColumn get drainRequested =>
      boolean().withDefault(const Constant(true))();
  IntColumn get connectionPhase => integer()
      .withDefault(const Constant(0))
      .check(connectionPhase.isBetweenValues(0, 9))();
  IntColumn get reconnectAttempt => integer()
      .withDefault(const Constant(0))
      .check(reconnectAttempt.isBiggerOrEqualValue(0))();
  DateTimeColumn get reconnectAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessfulSyncAt => dateTime().nullable()();

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
    DeviceLogMutations,
    SecurityPostures,
    PairwiseSessions,
    PairwiseSessionAlternates,
    Prekeys,
    PrekeyMaintenancePlans,
    MlsGroups,
    GroupControlEvents,
    GroupOutboundObjects,
    Conversations,
    Memberships,
    Messages,
    MessageEvents,
    StoredApplicationEvents,
    UnsupportedApplicationEvents,
    ApplicationSenderCounters,
    MessageReactions,
    Attachments,
    InboxEnvelopes,
    OutboxOperations,
    InboxEventDeduplications,
    PairwiseReplayMarkers,
    PairwiseOpenedPayloads,
    PairwiseLocalApplications,
    PairwiseConsumedPrekeys,
    StaleDeviceRefreshRequests,
    Receipts,
    PendingApplicationReceipts,
    VoiceRooms,
    HistoryTransfers,
    HistoryTransferBatches,
    SyncCheckpoints,
    LocalPreferences,
    QuarantineRecords,
  ],
)
final class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor, {StorageMigrationHooks? migrationHooks})
    : _migrationHooks = migrationHooks ?? const StorageMigrationHooks();

  static const currentSchemaVersion = 8;
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
        if (from < 3) {
          await migrator.addColumn(mlsGroups, mlsGroups.queueGapRecoveryState);
          await migrator.addColumn(
            inboxEnvelopes,
            inboxEnvelopes.opaqueEventId,
          );
          await migrator.addColumn(
            inboxEnvelopes,
            inboxEnvelopes.dependencyClass,
          );
          await migrator.addColumn(inboxEnvelopes, inboxEnvelopes.attemptCount);
          await migrator.addColumn(
            inboxEnvelopes,
            inboxEnvelopes.nextAttemptAt,
          );
          await migrator.addColumn(
            outboxOperations,
            outboxOperations.recipientUserId,
          );
          await migrator.addColumn(
            outboxOperations,
            outboxOperations.nextAttemptAt,
          );
          await migrator.addColumn(
            outboxOperations,
            outboxOperations.lastAttemptAt,
          );
          await migrator.addColumn(
            outboxOperations,
            outboxOperations.terminalAt,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.queueGapState,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.drainRequested,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.connectionPhase,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.reconnectAttempt,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.reconnectAt,
          );
          await migrator.addColumn(
            syncCheckpoints,
            syncCheckpoints.lastSuccessfulSyncAt,
          );
          await migrator.createTable(inboxEventDeduplications);
          await migrator.createTable(staleDeviceRefreshRequests);
        }
        if (from < 4) {
          await migrator.addColumn(secureSecrets, secureSecrets.stateRevision);
          await migrator.addColumn(
            devices,
            devices.lastSignedPrekeyRotationUnixDay,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.remoteUserId,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.sessionId,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.skippedKeyCount,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.disposition,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.repairState,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.repairAuthorization,
          );
          await migrator.addColumn(
            pairwiseSessions,
            pairwiseSessions.lastAuthenticatedAt,
          );
          await migrator.createTable(pairwiseSessionAlternates);
          await migrator.createTable(pairwiseReplayMarkers);
          await migrator.createTable(pairwiseOpenedPayloads);
          await migrator.createTable(pairwiseLocalApplications);
          await migrator.createTable(pairwiseConsumedPrekeys);
          await migrator.createTable(prekeyMaintenancePlans);
        }
        if (from < 5) {
          await migrator.addColumn(conversations, conversations.peerUserId);
          await migrator.addColumn(
            conversations,
            conversations.lastActivityEventId,
          );
          await migrator.addColumn(conversations, conversations.unreadCount);
          await migrator.addColumn(conversations, conversations.mutedUntil);
          await migrator.addColumn(
            conversations,
            conversations.draftCiphertext,
          );
          await migrator.addColumn(messages, messages.senderUserId);
          await migrator.addColumn(messages, messages.senderDeviceId);
          await migrator.addColumn(messages, messages.replyToMessageId);
          await migrator.addColumn(messages, messages.quoteFallbackCiphertext);
          await migrator.addColumn(messages, messages.orderingMs);
          await migrator.addColumn(messages, messages.orderingEventId);
          await migrator.addColumn(messages, messages.timestampState);
          await migrator.addColumn(messages, messages.deletedForEveryone);
          await migrator.addColumn(messages, messages.deletedForMe);
          await migrator.addColumn(messages, messages.pinned);
          await migrator.addColumn(messages, messages.unread);
          await migrator.createTable(storedApplicationEvents);
          await migrator.createTable(unsupportedApplicationEvents);
          await migrator.createTable(applicationSenderCounters);
          await migrator.createTable(messageReactions);
          await migrator.createTable(pendingApplicationReceipts);
        }
        if (from < 6) {
          await migrator.addColumn(conversations, conversations.pinned);
          await migrator.addColumn(messages, messages.starred);
        }
        if (from < 7) {
          Future<void> addIfMissing(
            String table,
            String column,
            Future<void> Function() add,
          ) async {
            final existing = await customSelect(
              'PRAGMA table_info("$table")',
            ).get();
            if (!existing.any((row) => row.read<String>('name') == column)) {
              await add();
            }
          }

          await addIfMissing(
            devices.actualTableName,
            devices.createdDate.$name,
            () => migrator.addColumn(devices, devices.createdDate),
          );
          await addIfMissing(
            devices.actualTableName,
            devices.decryptedLabel.$name,
            () => migrator.addColumn(devices, devices.decryptedLabel),
          );
          await addIfMissing(
            devices.actualTableName,
            devices.lastActiveDate.$name,
            () => migrator.addColumn(devices, devices.lastActiveDate),
          );
          await addIfMissing(
            devices.actualTableName,
            devices.isCurrentDevice.$name,
            () => migrator.addColumn(devices, devices.isCurrentDevice),
          );
          await addIfMissing(
            devices.actualTableName,
            devices.ownerListing.$name,
            () => migrator.addColumn(devices, devices.ownerListing),
          );
          await migrator.createTable(deviceLogMutations);
          await migrator.createTable(securityPostures);
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.sourceDeviceId.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.sourceDeviceId,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.targetDeviceId.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.targetDeviceId,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.direction.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.direction,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.state.$name,
            () => migrator.addColumn(historyTransfers, historyTransfers.state),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.nextBatchIndex.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.nextBatchIndex,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.groupReinviteRequired.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.groupReinviteRequired,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.queueGapRecoveryRequired.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.queueGapRecoveryRequired,
            ),
          );
          await addIfMissing(
            historyTransfers.actualTableName,
            historyTransfers.updatedAt.$name,
            () => migrator.addColumn(
              historyTransfers,
              historyTransfers.updatedAt,
            ),
          );
          await migrator.createTable(historyTransferBatches);
        }
        if (from < 8) {
          await migrator.addColumn(
            mlsGroups,
            mlsGroups.controlProjectionCiphertext,
          );
          await migrator.addColumn(mlsGroups, mlsGroups.controlRevision);
          await migrator.addColumn(mlsGroups, mlsGroups.controlStateHash);
          await migrator.addColumn(mlsGroups, mlsGroups.lifecycle);
          await migrator.addColumn(mlsGroups, mlsGroups.pendingMutationId);
          await migrator.addColumn(
            conversations,
            conversations.displayTitleCiphertext,
          );
          await migrator.createTable(groupControlEvents);
          await migrator.createTable(groupOutboundObjects);
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
