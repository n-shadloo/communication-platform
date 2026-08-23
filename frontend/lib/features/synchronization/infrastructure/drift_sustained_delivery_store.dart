import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/synchronization/application/ports/sustained_delivery_ports.dart';
import 'package:drift/drift.dart';

/// The user's sustained-delivery choice, in the encrypted preference table.
///
/// One row, one flag, and deliberately not a plaintext file or an Android
/// shared preference. The choice is a fact about its owner — that this person
/// arranged to keep receiving messages while the phone is in their pocket — and
/// it lives behind the same non-exportable Keystore-wrapped key as every other
/// durable fact this application holds.
///
/// Turning the capability off does not merely write `false`: the row is
/// deleted, so an installation nobody ever turned it on for and one that was
/// turned on and off again are indistinguishable on disk.
final class DriftSustainedDeliveryStore implements SustainedDeliveryStorePort {
  const DriftSustainedDeliveryStore(this.database);

  static const enabledKey = 'delivery.sustained_enabled.v1';

  final LocalDatabase database;

  @override
  Future<Result<bool>> readEnabled() async {
    try {
      final row =
          await (database.select(database.localPreferences)
                ..where((entry) => entry.preferenceKey.equals(enabledKey)))
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
  Future<Result<void>> writeEnabled({required bool enabled}) async {
    try {
      if (!enabled) {
        await (database.delete(
          database.localPreferences,
        )..where((entry) => entry.preferenceKey.equals(enabledKey))).go();
        return const Result.success(null);
      }
      await database
          .into(database.localPreferences)
          .insertOnConflictUpdate(
            LocalPreferencesCompanion.insert(
              preferenceKey: enabledKey,
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
