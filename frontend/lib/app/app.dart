import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Application root: global framework configuration and feature composition only.
class CommunicationPlatformApp extends StatelessWidget {
  const CommunicationPlatformApp({
    required this.environment,
    this.locale,
    super.key,
  });

  final AppEnvironment environment;
  final Locale? locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) {
      final localizations = AppLocalizations.of(context);
      return environment.isProduction
          ? localizations.appTitle
          : localizations.developmentAppTitle;
    },
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    ),
    home: BootstrapPage(isProduction: environment.isProduction),
  );
}
