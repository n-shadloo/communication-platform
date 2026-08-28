import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/settings/domain/appearance_model.dart';
import 'package:communication_platform/features/settings/infrastructure/drift_appearance_preference_store.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase database;
  late DriftAppearancePreferenceStore store;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    store = DriftAppearancePreferenceStore(database);
  });

  tearDown(() => database.close());

  test('an installation with no stored choice follows the phone', () async {
    expect(await store.read(), AppearancePreferences.followSystem);
  });

  test('a written choice survives a re-read', () async {
    const chosen = AppearancePreferences(
      theme: AppThemePreference.dark,
      language: AppLanguagePreference.persian,
    );
    expect(await store.write(chosen), isA<Success<void>>());
    expect(await store.read(), chosen);
  });

  test('both values are written together and independently readable', () async {
    await store.write(
      const AppearancePreferences(theme: AppThemePreference.light),
    );
    final stored = await store.read();
    expect(stored.theme, AppThemePreference.light);
    expect(stored.language, AppLanguagePreference.system);
  });

  test(
    'an unreadable row is read as "follow the phone", never as an error',
    () async {
      // A display preference may not become a reason the application will not
      // start, so a value this build cannot parse is treated as no value.
      await database
          .into(database.localPreferences)
          .insert(
            LocalPreferencesCompanion.insert(
              preferenceKey: DriftAppearancePreferenceStore.themeKey,
              valueCiphertext: Uint8List.fromList(const [0xff, 0xfe, 0xfd]),
              valueVersion: 1,
            ),
          );
      await database
          .into(database.localPreferences)
          .insert(
            LocalPreferencesCompanion.insert(
              preferenceKey: DriftAppearancePreferenceStore.languageKey,
              valueCiphertext: Uint8List.fromList(utf8.encode('klingon')),
              valueVersion: 1,
            ),
          );

      expect(await store.read(), AppearancePreferences.followSystem);
    },
  );

  test('the two rows are the only thing it touches', () async {
    await database
        .into(database.localPreferences)
        .insert(
          LocalPreferencesCompanion.insert(
            preferenceKey: 'disclosure.acknowledged_revision.v1',
            valueCiphertext: Uint8List.fromList(utf8.encode('7')),
            valueVersion: 1,
          ),
        );
    await store.write(
      const AppearancePreferences(theme: AppThemePreference.dark),
    );

    final rows = await database.select(database.localPreferences).get();
    expect(rows.map((row) => row.preferenceKey).toSet(), {
      'disclosure.acknowledged_revision.v1',
      DriftAppearancePreferenceStore.themeKey,
      DriftAppearancePreferenceStore.languageKey,
    });
  });

  test(
    'unreachable storage reports a failed write rather than pretending',
    () async {
      // A directory is not a database file, so nothing here can open. The
      // screen shows the choice as applied-but-not-saved, which is the truth;
      // reporting success would be a control that silently did nothing.
      final unreachable = LocalDatabase(
        NativeDatabase(File(Directory.systemTemp.path)),
      );
      final failing = DriftAppearancePreferenceStore(unreachable);
      expect(
        await failing.write(
          const AppearancePreferences(theme: AppThemePreference.dark),
        ),
        isA<FailureResult<void>>(),
      );
      expect(await failing.read(), AppearancePreferences.followSystem);
    },
  );
}
