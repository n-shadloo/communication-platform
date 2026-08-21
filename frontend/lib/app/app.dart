import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/app_environment_banner.dart';
import 'package:communication_platform/app/dependencies/message_alerts.dart';
import 'package:communication_platform/app/dependencies/message_delivery.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/app/routing/app_router.dart';
import 'package:communication_platform/features/app_shell/presentation/app_shell.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_route_state.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Application root: global framework configuration and feature composition only.
class CommunicationPlatformApp extends ConsumerStatefulWidget {
  const CommunicationPlatformApp({
    required this.environment,
    this.locale,
    this.themeMode = ThemeMode.system,
    this.routeGuard,
    this.shellStatus = const AppShellStatus(),
    this.initialLocation,
    this.bootstrapFlow,
    this.bootstrapPlatform = BootstrapPlatform.android,
    this.authenticationEnabled = false,
    super.key,
  });

  final AppEnvironment environment;
  final Locale? locale;
  final ThemeMode themeMode;
  final AppRouteGuard? routeGuard;
  final AppShellStatus shellStatus;
  final String? initialLocation;
  final BootstrapFlow? bootstrapFlow;
  final BootstrapPlatform bootstrapPlatform;
  final bool authenticationEnabled;

  @override
  ConsumerState<CommunicationPlatformApp> createState() =>
      _CommunicationPlatformAppState();
}

class _CommunicationPlatformAppState
    extends ConsumerState<CommunicationPlatformApp> {
  late final GoRouter _router;
  AuthenticationRouteState? _authenticationRouteState;
  ProviderSubscription<AuthenticationViewState>? _authenticationSubscription;
  ProviderSubscription<MessageDeliveryStage>? _deliverySubscription;
  ProviderSubscription<MessageAlertStage>? _alertSubscription;

  @override
  void initState() {
    super.initState();
    if (widget.authenticationEnabled) {
      final routeState = AuthenticationRouteState();
      _authenticationRouteState = routeState;
      _authenticationSubscription = ref.listenManual(
        authenticationControllerProvider,
        (previous, next) => routeState.update(next),
        fireImmediately: true,
      );
      // Message delivery is owned here, for the life of the application, and
      // deliberately not by a screen. `listenManual` is what makes that true:
      // subscriptions created in `build` are paused by Riverpod when their
      // widget leaves the view, and a paused delivery controller would stop
      // starting and stopping sessions the moment the user opened a route that
      // covered this one. Reading it is what instantiates it; the controller
      // itself decides when a session may run.
      _deliverySubscription = ref.listenManual(
        messageDeliveryControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
      // Alerts are owned here for the same reason and by the same mechanism,
      // and separately from delivery: a delivery session that fails to compose
      // still leaves messages in the database that arrived before it and have
      // never been announced.
      _alertSubscription = ref.listenManual(
        messageAlertControllerProvider,
        (previous, next) {},
        fireImmediately: true,
      );
    }
    _router = createAppRouter(
      environment: widget.environment,
      guard: widget.routeGuard,
      status: widget.shellStatus,
      initialLocation:
          widget.initialLocation ??
          (widget.bootstrapFlow == null ? '/chats' : '/connection'),
      bootstrapFlow: widget.bootstrapFlow,
      bootstrapPlatform: widget.bootstrapPlatform,
      authenticationRouteState: _authenticationRouteState,
    );
  }

  @override
  void dispose() {
    _alertSubscription?.close();
    _deliverySubscription?.close();
    _authenticationSubscription?.close();
    _authenticationRouteState?.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    onGenerateTitle: (context) =>
        widget.environment.userFacingTitle(AppLocalizations.of(context)),
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
