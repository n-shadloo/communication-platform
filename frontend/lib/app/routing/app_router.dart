import 'dart:async';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/app_shell/presentation/app_shell.dart';
import 'package:communication_platform/features/app_shell/presentation/structural_placeholder_page.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_pages.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_route_state.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/bootstrap/presentation/bootstrap_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

typedef AppRouteGuard =
    FutureOr<String?> Function(BuildContext context, GoRouterState state);

GoRouter createAppRouter({
  required AppEnvironment environment,
  AppRouteGuard? guard,
  AppShellStatus status = const AppShellStatus(),
  String initialLocation = '/chats',
  BootstrapFlow? bootstrapFlow,
  BootstrapPlatform bootstrapPlatform = BootstrapPlatform.android,
  AuthenticationRouteState? authenticationRouteState,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: authenticationRouteState,
  redirect: (context, state) {
    if (state.uri.path == '/') {
      return '/chats';
    }
    final authenticationRedirect = authenticationRouteState?.redirect(
      state.uri.path,
      state.uri.toString(),
    );
    if (authenticationRedirect != null) {
      return authenticationRedirect;
    }
    return guard?.call(context, state);
  },
  routes: [
    if (bootstrapFlow != null)
      GoRoute(
        path: '/connection',
        pageBuilder: (context, state) => _page(
          context,
          state,
          BootstrapPage(
            flow: bootstrapFlow,
            platform: bootstrapPlatform,
            isProduction: environment.isProduction,
            onResolved: (navigation) {
              switch (navigation.destination) {
                case BootstrapDestination.login:
                  context.go('/login', extra: navigation);
                case BootstrapDestination.application:
                  context.go(
                    navigation.offline ? '/chats?offline=true' : '/chats',
                  );
              }
            },
          ),
        ),
      ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) {
        final username = switch (state.extra) {
          BootstrapNavigation(:final rememberedUsername) => rememberedUsername,
          final String username => username,
          _ => null,
        };
        return _page(
          context,
          state,
          authenticationRouteState == null
              ? const LoginRouteBoundaryPage()
              : LoginPage(initialUsername: username),
        );
      },
    ),
    if (authenticationRouteState != null) ...[
      GoRoute(
        path: '/session-restoring',
        pageBuilder: (context, state) =>
            _page(context, state, const SessionRestorationPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) =>
            _page(context, state, const RegisterPage()),
      ),
      GoRoute(
        path: '/pending-activation',
        pageBuilder: (context, state) => _page(
          context,
          state,
          PendingActivationPage(username: state.extra as String?),
        ),
      ),
      GoRoute(
        path: '/security-notice',
        pageBuilder: (context, state) =>
            _page(context, state, const PreAuthSecurityNoticePage()),
      ),
      GoRoute(
        path: '/encryption-setup',
        pageBuilder: (context, state) =>
            _page(context, state, const EncryptionSetupRouteBoundaryPage()),
      ),
    ],
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        final bootstrapOffline = state.uri.queryParameters['offline'] == 'true';
        return AppShell(
          environment: environment,
          navigationShell: navigationShell,
          status: bootstrapOffline
              ? AppShellStatus(
                  connection: AppConnectionState.offline,
                  activeVoiceRoomName: status.activeVoiceRoomName,
                )
              : status,
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chats',
              pageBuilder: (context, state) => _page(
                context,
                state,
                const StructuralPlaceholderPage(
                  kind: StructuralPlaceholderKind.chats,
                ),
              ),
              routes: [
                GoRoute(
                  path: 'new',
                  pageBuilder: (context, state) => _page(
                    context,
                    state,
                    const StructuralPlaceholderPage(
                      kind: StructuralPlaceholderKind.newChat,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'sample-thread',
                  pageBuilder: (context, state) => _page(
                    context,
                    state,
                    const StructuralPlaceholderPage(
                      kind: StructuralPlaceholderKind.thread,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/voice-rooms',
              pageBuilder: (context, state) => _page(
                context,
                state,
                const StructuralPlaceholderPage(
                  kind: StructuralPlaceholderKind.voiceRooms,
                ),
              ),
              routes: [
                GoRoute(
                  path: 'new',
                  pageBuilder: (context, state) => _page(
                    context,
                    state,
                    const StructuralPlaceholderPage(
                      kind: StructuralPlaceholderKind.newRoom,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'sample-room',
                  pageBuilder: (context, state) => _page(
                    context,
                    state,
                    const StructuralPlaceholderPage(
                      kind: StructuralPlaceholderKind.room,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) => _page(
                context,
                state,
                const StructuralPlaceholderPage(
                  kind: StructuralPlaceholderKind.settings,
                ),
              ),
              routes: [
                GoRoute(
                  path: 'appearance',
                  pageBuilder: (context, state) => _page(
                    context,
                    state,
                    const StructuralPlaceholderPage(
                      kind: StructuralPlaceholderKind.appearance,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

Page<void> _page(BuildContext context, GoRouterState state, Widget child) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: reduceMotion ? Duration.zero : AppMotion.route,
    reverseTransitionDuration: reduceMotion ? Duration.zero : AppMotion.route,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) {
        return child;
      }
      final direction = Directionality.of(context) == TextDirection.ltr
          ? 1.0
          : -1.0;
      final offset = Tween<Offset>(
        begin: Offset(0.025 * direction, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: AppMotion.enter));
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          key: const ValueKey('app-route-spatial-transition'),
          position: animation.drive(offset),
          child: child,
        ),
      );
    },
  );
}
