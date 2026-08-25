import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/settings/application/ports/settings_ports.dart';
import 'package:communication_platform/features/settings/domain/appearance_model.dart';
import 'package:drift/drift.dart';

/// Theme and language, in the encrypted preference table.
///
/// Two rows holding two short words each, in the same table and behind the same
/// Keystore-wrapped key as every other durable preference, rather than in a
/// plain file or an Android shared preference. Neither value is protected
/// content; keeping them here means the logout wipe that destroys the database
/// key destroys them too, so a second account on the same phone does not
/// inherit the first one's screen.
///
/// A row this application cannot parse is read as "follow the phone" rather
/// than as an error, for the same reason the disclosure store treats an
/// unreadable row as no record: a display preference may never become a reason
/// the application will not start.
final class DriftAppearancePreferenceStore
    implements AppearancePreferenceStore {
  const DriftAppearancePreferenceStore(this.database);

  static const themeKey = 'appearance.theme.v1';
  static const languageKey = 'appearance.language.v1';

  final LocalDatabase database;

  @override
  Future<AppearancePreferences> read() async {
    try {
      final rows =
          await (database.select(database.localPreferences)..where(
                (entry) =>
                    entry.preferenceKey.isIn(const [themeKey, languageKey]),
              ))
              .get();
      return _fromRows(rows);
    } on Object {
      return AppearancePreferences.followSystem;
    }
  }

  @override
  Future<Result<void>> write(AppearancePreferences preferences) async {
    try {
      await database.writeTransaction<void>(() async {
        await _put(themeKey, preferences.theme.storageValue);
        await _put(languageKey, preferences.language.storageValue);
      });
      return const Result.success(null);
    } on Object {
      return const Result.failure(
        StorageFailure(StorageFailureKind.unavailable),
      );
    }
  }

  Future<void> _put(String key, String value) => database
      .into(database.localPreferences)
      .insertOnConflictUpdate(
        LocalPreferencesCompanion.insert(
          preferenceKey: key,
          valueCiphertext: Uint8List.fromList(utf8.encode(value)),
          valueVersion: 1,
        ),
      );

  AppearancePreferences _fromRows(List<LocalPreference> rows) {
    var preferences = AppearancePreferences.followSystem;
    for (final row in rows) {
      final value = _decode(row.valueCiphertext);
      if (value == null) {
        continue;
      }
      preferences = switch (row.preferenceKey) {
        themeKey => preferences.copyWith(
          theme: AppThemePreference.fromStorageValue(value),
        ),
        languageKey => preferences.copyWith(
          language: AppLanguagePreference.fromStorageValue(value),
        ),
        _ => preferences,
      };
    }
    return preferences;
  }

  String? _decode(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }
}
