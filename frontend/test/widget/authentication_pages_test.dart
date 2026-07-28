import 'dart:async';

import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/application/authentication_use_cases.dart';
import 'package:communication_platform/features/authentication/application/ports/authentication_ports.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login shows reviewed generic invalid-credentials copy', (
    tester,
  ) async {
    final harness = AuthenticationHarness(
      loginResult: const Result.failure(
        BackendFailure(BackendFailureCode.invalidCredentials),
      ),
    );
    await pumpAuthenticationApp(tester, harness);

    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'correct horse battery staple',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Username or password is incorrect.'), findsOneWidget);
    expect(find.textContaining('raw'), findsNothing);
    expect(harness.repository.loginCalls, 1);
  });

  testWidgets('inactive login routes to pending activation without polling', (
    tester,
  ) async {
    final harness = AuthenticationHarness(
      loginResult: const Result.failure(
        BackendFailure(BackendFailureCode.accountInactive),
      ),
    );
    await pumpAuthenticationApp(tester, harness);

    await tester.enterText(
      find.byKey(const ValueKey('login-username')),
      'alice',
    );
    await tester.enterText(
      find.byKey(const ValueKey('login-password')),
      'correct horse battery staple',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-activation-screen')),
      findsOneWidget,
    );
    expect(harness.repository.loginCalls, 1);
    expect(harness.repository.registerCalls, 0);

    await tester.tap(find.byKey(const ValueKey('pending-check-again')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-screen')), findsOneWidget);
    expect(harness.repository.loginCalls, 1);
    final password = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('login-password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(password.controller.text, isEmpty);
  });

  testWidgets('registration normalizes and reaches pending activation', (
    tester,
  ) async {
    final harness = AuthenticationHarness();
    await pumpAuthenticationApp(tester, harness);
    final createAccount = find.text('Create account');
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('register-username')),
      'ALICE',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register-password')),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.byKey(const ValueKey('register-confirm-password')),
      'correct horse battery staple',
    );
    await tester.pump();
    final registerSubmit = find.byKey(const ValueKey('register-submit'));
    await tester.ensureVisible(registerSubmit);
    await tester.tap(registerSubmit);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('pending-activation-screen')),
      findsOneWidget,
    );
    expect(harness.repository.registerCalls, 1);
    expect(harness.repository.lastUsername, 'alice');
    expect(harness.repository.loginCalls, 0);
    expect(
      find.textContaining('There is no automatic activation check'),
      findsOneWidget,
    );
  });

  testWidgets('Persian authentication screen is right-to-left and localized', (
    tester,
  ) async {
    final harness = AuthenticationHarness();
    await pumpAuthenticationApp(tester, harness, locale: const Locale('fa'));

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('نام کاربری'), findsOneWidget);
    expect(find.text('رمز عبور'), findsOneWidget);
  });
}

Future<void> pumpAuthenticationApp(
  WidgetTester tester,
  AuthenticationHarness harness, {
  Locale locale = const Locale('en'),
}) async {
  addTearDown(harness.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authenticationUseCasesProvider.overrideWithValue(harness.useCases),
      ],
      child: CommunicationPlatformApp(
        environment: AppEnvironment.production,
        locale: locale,
        initialLocation: '/login',
        authenticationEnabled: true,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class AuthenticationHarness {
  AuthenticationHarness({
    Result<AccountSessionGrant>? loginResult,
    Result<AccountRegistration>? registrationResult,
  }) : repository = WidgetAuthenticationRepository(
         loginResult:
             loginResult ??
             Result.success(
               AccountSessionGrant(
                 accessToken: 'register-access',
                 accessExpiresAt: DateTime.utc(2026, 7, 28, 12),
                 userId: userId,
                 scope: AccountSessionScope.register,
               ),
             ),
         registrationResult:
             registrationResult ??
             const Result.success(AccountRegistration(userId: userId)),
       ),
       session = WidgetAuthenticationSession(),
       lifecycle = WidgetLifecycle() {
    useCases = AuthenticationUseCases(
      register: RegisterAccount(repository),
      login: LoginAccount(repository, session),
      restore: RestoreAccountSession(session),
      logout: LogoutAccount(session),
      lifecycle: lifecycle,
    );
  }

  final WidgetAuthenticationRepository repository;
  final WidgetAuthenticationSession session;
  final WidgetLifecycle lifecycle;
  late final AuthenticationUseCases useCases;

  Future<void> close() => lifecycle.close();
}

const userId = '6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10';

final class WidgetAuthenticationRepository
    implements AccountAuthenticationRepository {
  WidgetAuthenticationRepository({
    required this.loginResult,
    required this.registrationResult,
  });

  final Result<AccountSessionGrant> loginResult;
  final Result<AccountRegistration> registrationResult;
  int loginCalls = 0;
  int registerCalls = 0;
  String? lastUsername;

  @override
  Future<Result<AccountSessionGrant>> login({
    required String username,
    required String password,
    String? deviceId,
  }) async {
    loginCalls += 1;
    lastUsername = username;
    return loginResult;
  }

  @override
  Future<Result<AccountRegistration>> register({
    required String username,
    required String password,
  }) async {
    registerCalls += 1;
    lastUsername = username;
    return registrationResult;
  }
}

final class WidgetAuthenticationSession implements AuthenticationSessionPort {
  @override
  Future<Result<AccountSessionBoundary>> acceptLogin({
    required String username,
    required AccountSessionGrant grant,
    required bool replacedKnownDevice,
  }) async => Result.success(
    AccountSessionBoundary(
      userId: grant.userId,
      deviceId: grant.deviceId,
      scope: grant.scope,
      offline: false,
    ),
  );

  @override
  Future<LoginHint> readLoginHint() async => const LoginHint();

  @override
  Future<Result<AccountSessionBoundary>> restore() async =>
      const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      );

  @override
  Future<void> logout() async {}
}

final class WidgetLifecycle implements AuthenticationLifecyclePort {
  final StreamController<AuthenticationTermination> _controller =
      StreamController<AuthenticationTermination>.broadcast();

  @override
  Stream<AuthenticationTermination> get terminations => _controller.stream;

  Future<void> close() => _controller.close();
}
