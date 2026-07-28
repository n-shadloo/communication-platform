import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_route_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('protected deep link restores deterministically after full session', () {
    final route = AuthenticationRouteState();

    expect(
      route.redirect('/settings', '/settings?section=security'),
      '/session-restoring',
    );
    route.update(
      const AuthenticationViewState(
        access: AuthenticationRouteAccess.fullScope,
        operation: AuthenticationOperation.idle,
      ),
    );
    expect(
      route.redirect('/session-restoring', '/session-restoring'),
      '/settings?section=security',
    );
    route.dispose();
  });

  test(
    'signed-out, register-scope, and offline-full boundaries are explicit',
    () {
      final route = AuthenticationRouteState();
      route.update(
        const AuthenticationViewState(
          access: AuthenticationRouteAccess.signedOut,
          operation: AuthenticationOperation.idle,
        ),
      );
      expect(route.redirect('/chats', '/chats'), '/login');

      route.update(
        const AuthenticationViewState(
          access: AuthenticationRouteAccess.registerScope,
          operation: AuthenticationOperation.idle,
        ),
      );
      expect(route.redirect('/chats', '/chats'), '/encryption-setup');
      expect(route.redirect('/encryption-setup', '/encryption-setup'), isNull);

      route.update(
        const AuthenticationViewState(
          access: AuthenticationRouteAccess.secureSetup,
          operation: AuthenticationOperation.idle,
        ),
      );
      expect(route.redirect('/chats', '/chats'), '/encryption-setup');
      expect(route.redirect('/encryption-setup', '/encryption-setup'), isNull);

      route.update(
        const AuthenticationViewState(
          access: AuthenticationRouteAccess.offlineFullScope,
          operation: AuthenticationOperation.idle,
        ),
      );
      expect(route.redirect('/chats', '/chats'), isNull);
      route.dispose();
    },
  );

  test('pending activation cannot escape into authenticated routes', () {
    final route = AuthenticationRouteState();
    route.update(
      const AuthenticationViewState(
        access: AuthenticationRouteAccess.pendingActivation,
        operation: AuthenticationOperation.idle,
        username: 'alice',
      ),
    );

    expect(route.redirect('/settings', '/settings'), '/pending-activation');
    expect(
      route.redirect('/pending-activation', '/pending-activation'),
      isNull,
    );
    route.dispose();
  });
}
