import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/disclosure_acknowledgement_ports.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/drift.dart';

/// The accepted disclosure revision, in the encrypted preference table.
///
/// One row holding one small integer, written as text so that a future format
/// change is a parse decision rather than a migration. It is deliberately not a
/// plain file or an Android shared preference: it is a fact about its owner —
/// that this person was shown a particular statement and answered it — and it
/// belongs behind the same non-exportable Keystore-wrapped key as everything
/// else durable here (ADR-052).
///
/// Unlike the sustained-delivery flag, the row is never deleted on any user
/// action. There is no "un-accept": erasing it would silently re-present a
/// statement the user has already answered, and the only thing that clears it
/// is clearing application data, which destroys the account's local state
/// anyway.
final class DriftDisclosureAcknowledgementStore
    implements DisclosureAcknowledgementStore {
  const DriftDisclosureAcknowledgementStore(this.database);

  static const revisionKey = 'disclosure.acknowledged_revision.v1';

  final LocalDatabase database;

  @override
  Future<Result<int>> readAcknowledgedRevision() async {
    try {
      final row =
          await (database.select(database.localPreferences)
                ..where((entry) => entry.preferenceKey.equals(revisionKey)))
              .getSingleOrNull();
      if (row == null) {
        return const Result.success(0);
      }
      // A row this application cannot parse is treated as no record at all,
      // never as a current one: the failure direction that shows a notice again
      // is always safer than the one that withholds it.
      final parsed = int.tryParse(utf8.decode(row.valueCiphertext).trim());
      return Result.success(parsed == null || parsed < 0 ? 0 : parsed);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  @override
  Future<Result<void>> recordAcknowledgedRevision(int revision) async {
    try {
      await database.writeTransaction<void>(() async {
        final row =
            await (database.select(database.localPreferences)
                  ..where((entry) => entry.preferenceKey.equals(revisionKey)))
                .getSingleOrNull();
        final existing = row == null
            ? 0
            : int.tryParse(utf8.decode(row.valueCiphertext).trim()) ?? 0;
        if (existing >= revision) {
          return;
        }
        await database
            .into(database.localPreferences)
            .insertOnConflictUpdate(
              LocalPreferencesCompanion.insert(
                preferenceKey: revisionKey,
                valueCiphertext: Uint8List.fromList(
                  utf8.encode(revision.toString()),
                ),
                valueVersion: 1,
              ),
            );
      });
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }
}
