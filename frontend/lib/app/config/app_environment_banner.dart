import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';

/// The single place that decides which builds warn about their configuration and
/// what that warning names them.
///
/// Beta builds are installed by external testers, so they must never be labelled
/// as development.
extension AppEnvironmentBanner on AppEnvironment {
  /// The persistent configuration banner for this build, or null when the build
  /// is production and must show no banner at all.
  String? configurationBanner(AppLocalizations l10n) => switch (this) {
    AppEnvironment.development => l10n.developmentConfiguration,
    AppEnvironment.beta => l10n.betaConfiguration,
    AppEnvironment.production => null,
  };
}
