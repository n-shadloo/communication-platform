import 'package:communication_platform/config/app_environment.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class BootstrapApp extends StatelessWidget {
  const BootstrapApp({required this.environment, this.locale, super.key});

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
    home: _BootstrapHome(environment: environment),
  );
}

class _BootstrapHome extends StatelessWidget {
  const _BootstrapHome({required this.environment});

  final AppEnvironment environment;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!environment.isProduction)
              Semantics(
                container: true,
                liveRegion: true,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      localizations.developmentConfiguration,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        localizations.appTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        localizations.foundationReady,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
