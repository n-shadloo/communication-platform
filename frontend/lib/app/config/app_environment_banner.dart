import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';

/// The single place that decides how a build names itself to the person using
/// it: the window title Android shows in the task switcher, and the persistent
/// configuration banner.
///
/// Beta builds are installed by external testers, so they must never be
/// labelled as development — in either surface. The launcher label lives in the
/// Android product flavor and reads "Communication Platform (Experimental)";
/// [userFacingTitle] has to agree with it, or one build presents two identities.
extension AppEnvironmentBanner on AppEnvironment {
  /// The application title shown to the user, per build.
  String userFacingTitle(AppLocalizations l10n) => switch (this) {
    AppEnvironment.development => l10n.developmentAppTitle,
    AppEnvironment.beta => l10n.experimentalAppTitle,
    AppEnvironment.production => l10n.appTitle,
  };

  /// The persistent configuration banner for this build, or null when the build
  /// is production and must show no banner at all.
  String? configurationBanner(AppLocalizations l10n) => switch (this) {
    AppEnvironment.development => l10n.developmentConfiguration,
    AppEnvironment.beta => l10n.betaConfiguration,
    AppEnvironment.production => null,
  };
}
