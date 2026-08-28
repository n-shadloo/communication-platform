import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_linked_device_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase database;
  late DriftLinkedDeviceRepository repository;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    repository = DriftLinkedDeviceRepository(database);
  });

  tearDown(() => database.close());

  test(
    'authenticated source disappearance marks only receiver work no-source',
    () async {
      await database
          .into(database.historyTransfers)
          .insert(
            HistoryTransfersCompanion.insert(
              transferId: '10000000000040008000000000000001',
              manifestCiphertext: Uint8List.fromList([1]),
              sourceDeviceId: const Value(
                '10000000-0000-4000-8000-000000000001',
              ),
              targetDeviceId: const Value(
                '10000000-0000-4000-8000-000000000003',
              ),
              state: const Value(1),
              sourceCompleteness: 0,
            ),
          );
      await database
          .into(database.historyTransfers)
          .insert(
            HistoryTransfersCompanion.insert(
              transferId: '10000000000040008000000000000002',
              manifestCiphertext: Uint8List.fromList([2]),
              sourceDeviceId: const Value(
                '10000000-0000-4000-8000-000000000002',
              ),
              targetDeviceId: const Value(
                '10000000-0000-4000-8000-000000000003',
              ),
              state: const Value(2),
              sourceCompleteness: 0,
            ),
          );
      await database
          .into(database.historyTransfers)
          .insert(
            HistoryTransfersCompanion.insert(
              transferId: '10000000000040008000000000000003',
              manifestCiphertext: Uint8List.fromList([3]),
              sourceDeviceId: const Value(
                '10000000-0000-4000-8000-000000000001',
              ),
              targetDeviceId: const Value(
                '10000000-0000-4000-8000-000000000003',
              ),
              direction: const Value(1),
              state: const Value(1),
              sourceCompleteness: 0,
            ),
          );

      final result = await repository.markMissingHistorySources({
        '10000000-0000-4000-8000-000000000002',
        '10000000-0000-4000-8000-000000000003',
      });

      expect(result, isA<Success<void>>());
      final rows = await (database.select(
        database.historyTransfers,
      )..orderBy([(row) => OrderingTerm.asc(row.transferId)])).get();
      expect(rows.map((row) => row.state), [4, 2, 1]);
    },
  );
}
