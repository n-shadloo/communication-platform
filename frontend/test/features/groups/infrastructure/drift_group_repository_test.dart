import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/group_use_cases.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/development_in_memory_group_mls.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = '00000000-0000-0000-0000-000000000001';
const _member = '00000000-0000-0000-0000-000000000002';
const _missing = '00000000-0000-0000-0000-000000000003';
const _device = '10000000-0000-0000-0000-000000000001';

void main() {
  late LocalDatabase database;
  late DriftGroupRepository repository;

  setUp(() async {
    database = LocalDatabase(NativeDatabase.memory());
    repository = DriftGroupRepository(database);
    await _insertUser(database, _owner);
    await _insertUser(database, _member);
  });

  tearDown(() => database.close());

  test(
    'MLS state, control, membership, projection, and outbox commit atomically',
    () async {
      final result = await _create(repository, _member, seed: 100);
      expect(result, isA<Success<GroupState>>());
      final state = (result as Success<GroupState>).value;

      expect(await database.select(database.mlsGroups).get(), hasLength(1));
      expect(
        await database.select(database.groupControlEvents).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.groupOutboundObjects).get(),
        hasLength(1),
      );
      expect(await database.select(database.memberships).get(), hasLength(2));
      expect(
        (await database.select(database.groupOutboundObjects).getSingle())
            .deliveryState,
        0,
      );
      expect(
        (await repository.readGroup(state.groupId)),
        isA<Success<GroupState?>>(),
      );
    },
  );

  test(
    'foreign-key persistence failure rolls back every group table',
    () async {
      final result = await _create(repository, _missing, seed: 110);

      expect(result, isA<FailureResult<GroupState>>());
      expect(
        (result as FailureResult<GroupState>).failure,
        isA<StorageFailure>(),
      );
      expect(await database.select(database.mlsGroups).get(), isEmpty);
      expect(await database.select(database.conversations).get(), isEmpty);
      expect(await database.select(database.groupControlEvents).get(), isEmpty);
      expect(
        await database.select(database.groupOutboundObjects).get(),
        isEmpty,
      );
      expect(await database.select(database.memberships).get(), isEmpty);
    },
  );

  test(
    'queue gap overlays a blocking rejoin state without guessing MLS state',
    () async {
      final created = await _create(repository, _member, seed: 120);
      final state = (created as Success<GroupState>).value;
      final before = await repository.readOpaqueMlsState(state.groupId);

      await (database.update(database.mlsGroups)
            ..where((row) => row.groupId.equals(state.groupId)))
          .write(const MlsGroupsCompanion(queueGapRecoveryState: Value(1)));
      final projection = await repository.readGroup(state.groupId);
      final after = await repository.readOpaqueMlsState(state.groupId);

      expect(
        (projection as Success<GroupState?>).value!.lifecycle,
        GroupLifecycle.queueGapRejoinRequired,
      );
      expect(
        (after as Success<Uint8List?>).value,
        orderedEquals((before as Success<Uint8List?>).value!),
      );
    },
  );
}

Future<Result<GroupState>> _create(
  DriftGroupRepository repository,
  String memberId, {
  required int seed,
}) =>
    CreateGroup(
      repository: repository,
      crypto: DevelopmentInMemoryGroupMls.forTests(seed: seed),
      clock: const _Clock(),
      developmentPreviewOnly: true,
    )(
      currentUserId: _owner,
      currentDeviceId: _device,
      ownerDisplayName: 'Owner',
      metadata: const GroupMetadata(name: 'Team'),
      selectedMembers: [
        GroupMember(
          userId: memberId,
          displayName: 'Member',
          role: GroupRole.member,
        ),
      ],
    );

Future<void> _insertUser(LocalDatabase database, String id) => database
    .into(database.users)
    .insert(
      UsersCompanion.insert(
        userId: id,
        activated: true,
        directoryEntryCiphertext: Uint8List.fromList([1]),
        localState: 0,
      ),
    );

final class _Clock implements TimeSource {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 8, 2, 12);
}
