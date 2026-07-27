import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/app/routing/app_router.dart';
import 'package:communication_platform/features/app_shell/presentation/app_shell.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Application root: global framework configuration and feature composition only.
class CommunicationPlatformApp extends StatefulWidget {
  const CommunicationPlatformApp({
    required this.environment,
    this.locale,
    this.themeMode = ThemeMode.system,
    this.routeGuard,
    this.shellStatus = const AppShellStatus(),
    this.initialLocation = '/chats',
    super.key,
  });

  final AppEnvironment environment;
  final Locale? locale;
  final ThemeMode themeMode;
  final AppRouteGuard? routeGuard;
  final AppShellStatus shellStatus;
  final String initialLocation;

  @override
  State<CommunicationPlatformApp> createState() =>
      _CommunicationPlatformAppState();
}

class _CommunicationPlatformAppState extends State<CommunicationPlatformApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(
      environment: widget.environment,
      guard: widget.routeGuard,
      status: widget.shellStatus,
      initialLocation: widget.initialLocation,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) {
      final localizations = AppLocalizations.of(context);
      return widget.environment.isProduction
          ? localizations.appTitle
          : localizations.developmentAppTitle;
    },
    locale: widget.locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    themeMode: widget.themeMode,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    highContrastTheme: AppTheme.highContrastLight(),
    highContrastDarkTheme: AppTheme.highContrastDark(),
    themeAnimationDuration: AppMotion.state,
    restorationScopeId: 'communication-platform-app',
    routerConfig: _router,
    builder: (context, child) =>
        AppDesignSystem(child: child ?? const SizedBox.shrink()),
  );
}
