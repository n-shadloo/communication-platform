/// Which of the application's own themes the user asked for.
///
/// Deliberately three values and not four: high contrast is not a choice here.
/// Android owns that switch, `MaterialApp` selects the high-contrast palette
/// from `MediaQuery.highContrast`, and offering a second control beside the
/// system one would let the two disagree about a setting that exists for
/// accessibility.
enum AppThemePreference {
  /// Follow the phone. The default, and what an install with no stored row has.
  system,
  light,
  dark;

  static AppThemePreference fromStorageValue(String value) =>
      switch (value.trim()) {
        'light' => AppThemePreference.light,
        'dark' => AppThemePreference.dark,
        _ => AppThemePreference.system,
      };

  String get storageValue => name;
}

/// Which of the two shipped languages the user asked for.
///
/// English and Persian are the release set (ADR-016). `system` means "whatever
/// the phone says", which is what an install with no stored row has, and is the
/// only value that can resolve to neither when the phone is set to a third
/// language — `MaterialApp` then falls back to the first supported locale.
enum AppLanguagePreference {
  system,
  english,
  persian;

  static AppLanguagePreference fromStorageValue(String value) =>
      switch (value.trim()) {
        'english' => AppLanguagePreference.english,
        'persian' => AppLanguagePreference.persian,
        _ => AppLanguagePreference.system,
      };

  String get storageValue => name;

  /// The BCP-47 language subtag this preference pins, or null for the phone's.
  String? get languageCode => switch (this) {
    AppLanguagePreference.system => null,
    AppLanguagePreference.english => 'en',
    AppLanguagePreference.persian => 'fa',
  };
}

/// The client-only display preferences of one installation.
///
/// Client-only in the strict sense: nothing here is sent anywhere, nothing here
/// is derived from anything the server said, and nothing here is protected
/// content. It is stored in the encrypted database all the same, because that
/// is where this application's durable state lives and a second store would be
/// a second thing to wipe.
final class AppearancePreferences {
  const AppearancePreferences({
    this.theme = AppThemePreference.system,
    this.language = AppLanguagePreference.system,
  });

  /// What an installation has before anybody opens the Appearance screen.
  static const followSystem = AppearancePreferences();

  final AppThemePreference theme;
  final AppLanguagePreference language;

  AppearancePreferences copyWith({
    AppThemePreference? theme,
    AppLanguagePreference? language,
  }) => AppearancePreferences(
    theme: theme ?? this.theme,
    language: language ?? this.language,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearancePreferences &&
      other.theme == theme &&
      other.language == language;

  @override
  int get hashCode => Object.hash(theme, language);

  @override
  String toString() =>
      'AppearancePreferences(theme: ${theme.name}, language: ${language.name})';
}
