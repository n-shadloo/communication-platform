import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:flutter/foundation.dart';

final class AuthenticationRouteState extends ChangeNotifier {
  AuthenticationRouteAccess _access = AuthenticationRouteAccess.dormant;
  String? _intendedLocation;

  AuthenticationRouteAccess get access => _access;

  void update(AuthenticationViewState state) {
    if (_access == state.access) {
      return;
    }
    _access = state.access;
    notifyListeners();
  }

  String? redirect(String path, String location) {
    final isConnection = path == '/connection';
    final isSecurity = path == '/security-notice';
    final isLogin = path == '/login';
    final isRegister = path == '/register';
    final isPending = path == '/pending-activation';
    final isRestoring = path == '/session-restoring';
    final isEnrollment = path == '/encryption-setup';
    final isPublic =
        isConnection ||
        isSecurity ||
        isLogin ||
        isRegister ||
        isPending ||
        isRestoring;

    switch (_access) {
      case AuthenticationRouteAccess.dormant:
        if (!isPublic) {
          _intendedLocation = location;
          return '/session-restoring';
        }
      case AuthenticationRouteAccess.signedOut:
        if (!isPublic || isRestoring || isPending || isEnrollment) {
          _intendedLocation ??= isPublic ? null : location;
          return '/login';
        }
      case AuthenticationRouteAccess.pendingActivation:
        if (!isConnection && !isSecurity && !isPending) {
          return '/pending-activation';
        }
      case AuthenticationRouteAccess.registerScope:
        if (!isConnection && !isSecurity && !isEnrollment) {
          return '/encryption-setup';
        }
      case AuthenticationRouteAccess.fullScope ||
          AuthenticationRouteAccess.offlineFullScope:
        if (isLogin || isRegister || isPending || isRestoring) {
          final target = _intendedLocation ?? '/chats';
          _intendedLocation = null;
          return target;
        }
    }
    return null;
  }
}
