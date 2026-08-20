import 'dart:async';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/devices/presentation/security_notice_sections.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({this.initialUsername, super.key});

  final String? initialUsername;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  late final TextEditingController _username;
  final TextEditingController _password = TextEditingController();
  bool _usernameTouched = false;
  bool _passwordTouched = false;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.initialUsername ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = ref.read(authenticationControllerProvider.notifier);
      controller.enterSignedOut(rememberedUsername: widget.initialUsername);
      final remembered = ref.read(authenticationControllerProvider).username;
      if (_username.text.isEmpty && remembered != null) {
        _username.text = remembered;
      }
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password
      ..clear()
      ..dispose();
    super.dispose();
  }

  bool get _valid =>
      AuthenticationInputPolicy.isUsernameValid(_username.text) &&
      AuthenticationInputPolicy.isPasswordValid(_password.text);

  Future<void> _submit() async {
    setState(() {
      _usernameTouched = true;
      _passwordTouched = true;
    });
    if (!_valid) {
      return;
    }
    final succeeded = await ref
        .read(authenticationControllerProvider.notifier)
        .login(username: _username.text, password: _password.text);
    if (!mounted) {
      return;
    }
    if (succeeded ||
        ref.read(authenticationControllerProvider).access ==
            AuthenticationRouteAccess.pendingActivation) {
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(authenticationControllerProvider);
    final busy = state.operation == AuthenticationOperation.login;
    final usernameError =
        _usernameTouched &&
            !AuthenticationInputPolicy.isUsernameValid(_username.text)
        ? l10n.authUsernameFormatError
        : null;
    final passwordError =
        _passwordTouched &&
            !AuthenticationInputPolicy.isPasswordValid(_password.text)
        ? l10n.authPasswordLengthError
        : null;

    return _AuthenticationScaffold(
      formKey: const ValueKey('login-screen'),
      title: l10n.authLoginTitle,
      subtitle: l10n.authLoginSubtitle,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.message != null) ...[
              _AuthenticationNotice(
                message: _localizedMessage(l10n, state.message!),
              ),
              const SizedBox(height: AppSpacing.x4),
            ],
            AppField(
              key: const ValueKey('login-username'),
              label: l10n.authUsernameLabel,
              controller: _username,
              enabled: !busy,
              error: usernameError,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              onChanged: (_) => setState(() => _usernameTouched = true),
              maxLength: 32,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppField(
              key: const ValueKey('login-password'),
              label: l10n.authPasswordLabel,
              controller: _password,
              enabled: !busy,
              obscureText: true,
              error: passwordError,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) => setState(() => _passwordTouched = true),
              onSubmitted: (_) => _valid && !busy ? _submit() : null,
              maxLength: 256,
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              l10n.authPasswordPurpose,
              style: context.tokens.typography.compact.copyWith(
                color: context.tokens.colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.x6),
            AppButton(
              key: const ValueKey('login-submit'),
              label: busy ? l10n.authLoggingInAction : l10n.authLoginAction,
              onPressed: _valid && !busy ? _submit : null,
            ),
            const SizedBox(height: AppSpacing.x2),
            AppButton(
              label: l10n.authCreateAccountAction,
              kind: AppButtonKind.ghost,
              onPressed: busy ? null : () => context.go('/register'),
            ),
            const SizedBox(height: AppSpacing.x2),
            AppButton(
              label: l10n.authSecurityNoticeAction,
              kind: AppButtonKind.ghost,
              leading: AppIcons.security,
              onPressed: busy ? null : () => context.push('/security-notice'),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  bool _usernameTouched = false;
  bool _passwordTouched = false;
  bool _confirmationTouched = false;

  @override
  void dispose() {
    _username.dispose();
    _password
      ..clear()
      ..dispose();
    _confirmation
      ..clear()
      ..dispose();
    super.dispose();
  }

  bool get _valid =>
      AuthenticationInputPolicy.isUsernameValid(_username.text) &&
      AuthenticationInputPolicy.isPasswordValid(_password.text) &&
      _password.text == _confirmation.text;

  Future<void> _submit() async {
    setState(() {
      _usernameTouched = true;
      _passwordTouched = true;
      _confirmationTouched = true;
    });
    if (!_valid) {
      return;
    }
    final succeeded = await ref
        .read(authenticationControllerProvider.notifier)
        .register(username: _username.text, password: _password.text);
    if (!mounted || !succeeded) {
      return;
    }
    final normalized = AuthenticationInputPolicy.normalizeUsername(
      _username.text,
    );
    _password.clear();
    _confirmation.clear();
    context.go('/pending-activation', extra: normalized);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(authenticationControllerProvider);
    final busy = state.operation == AuthenticationOperation.register;
    final usernameFormatError =
        _usernameTouched &&
            !AuthenticationInputPolicy.isUsernameValid(_username.text)
        ? l10n.authUsernameFormatError
        : null;
    final usernameError = state.message == AuthenticationMessage.usernameTaken
        ? l10n.authUsernameTakenMessage
        : usernameFormatError;
    final passwordError =
        _passwordTouched &&
            !AuthenticationInputPolicy.isPasswordValid(_password.text)
        ? l10n.authPasswordLengthError
        : null;
    final confirmationError =
        _confirmationTouched && _password.text != _confirmation.text
        ? l10n.authPasswordsMismatchError
        : null;
    final globalMessage =
        state.message != null &&
            state.message != AuthenticationMessage.usernameTaken
        ? _localizedMessage(l10n, state.message!)
        : null;

    return _AuthenticationScaffold(
      formKey: const ValueKey('register-screen'),
      title: l10n.authRegisterTitle,
      subtitle: l10n.authRegisterSubtitle,
      leading: AppIconButton(
        icon: AppIcons.back,
        semanticLabel: l10n.authBackToLoginAction,
        kind: AppButtonKind.ghost,
        onPressed: busy ? null : () => context.go('/login'),
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (globalMessage != null) ...[
              _AuthenticationNotice(message: globalMessage),
              const SizedBox(height: AppSpacing.x4),
            ],
            AppField(
              key: const ValueKey('register-username'),
              label: l10n.authUsernameLabel,
              controller: _username,
              enabled: !busy,
              error: usernameError,
              description: l10n.authUsernameHint,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              onChanged: (_) => setState(() => _usernameTouched = true),
              maxLength: 32,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppField(
              key: const ValueKey('register-password'),
              label: l10n.authPasswordLabel,
              controller: _password,
              enabled: !busy,
              obscureText: true,
              error: passwordError,
              description: l10n.authPasswordHint,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() => _passwordTouched = true),
              maxLength: 256,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppField(
              key: const ValueKey('register-confirm-password'),
              label: l10n.authConfirmPasswordLabel,
              controller: _confirmation,
              enabled: !busy,
              obscureText: true,
              error: confirmationError,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() => _confirmationTouched = true),
              onSubmitted: (_) => _valid && !busy ? _submit() : null,
              maxLength: 256,
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              l10n.authPasswordPurpose,
              style: context.tokens.typography.compact.copyWith(
                color: context.tokens.colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.x6),
            AppButton(
              key: const ValueKey('register-submit'),
              label: busy
                  ? l10n.authCreatingAccountAction
                  : l10n.authCreateAccountAction,
              onPressed: _valid && !busy ? _submit : null,
            ),
            const SizedBox(height: AppSpacing.x2),
            AppButton(
              label: l10n.authSecurityNoticeAction,
              kind: AppButtonKind.ghost,
              leading: AppIcons.security,
              onPressed: busy ? null : () => context.push('/security-notice'),
            ),
          ],
        ),
      ),
    );
  }
}

class PendingActivationPage extends ConsumerWidget {
  const PendingActivationPage({this.username, super.key});

  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(authenticationControllerProvider);
    final remembered = username ?? state.username;
    if (remembered == null || remembered.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.go('/login');
        }
      });
    }
    return _AuthenticationScaffold(
      formKey: const ValueKey('pending-activation-screen'),
      title: l10n.authPendingTitle,
      subtitle: l10n.authPendingMessage,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.colors.accentSoft,
              borderRadius: AppRadii.card,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Text(
                l10n.authPendingNoPollingMessage,
                style: context.tokens.typography.body,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            key: const ValueKey('pending-check-again'),
            label: l10n.authCheckAgainAction,
            onPressed: remembered == null
                ? null
                : () {
                    ref
                        .read(authenticationControllerProvider.notifier)
                        .returnToLogin();
                    context.go('/login', extra: remembered);
                  },
          ),
          const SizedBox(height: AppSpacing.x2),
          AppButton(
            label: l10n.authBackToLoginAction,
            kind: AppButtonKind.ghost,
            onPressed: () {
              ref
                  .read(authenticationControllerProvider.notifier)
                  .returnToLogin();
              context.go('/login', extra: remembered);
            },
          ),
        ],
      ),
    );
  }
}

class SessionRestorationPage extends ConsumerStatefulWidget {
  const SessionRestorationPage({super.key});

  @override
  ConsumerState<SessionRestorationPage> createState() =>
      _SessionRestorationPageState();
}

class _SessionRestorationPageState
    extends ConsumerState<SessionRestorationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(authenticationControllerProvider.notifier).restore(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('session-restoration-screen'),
    body: SafeArea(
      child: AppStatePanel.loading(
        title: AppLocalizations.of(context).authRestoringSession,
      ),
    ),
  );
}

class EncryptionSetupRouteBoundaryPage extends StatelessWidget {
  const EncryptionSetupRouteBoundaryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('encryption-setup-route-boundary'),
    body: SafeArea(
      child: AppStatePanel.empty(
        title: AppLocalizations.of(context).authSecureSetupBoundaryTitle,
        message: AppLocalizations.of(context).authSecureSetupBoundaryMessage,
      ),
    ),
  );
}

/// The re-viewable copy of the one security notice.
///
/// Reached from the pre-login links and from Settings, both of which the UI
/// specification has always required. It renders exactly the content the
/// mandatory enrollment step renders, minus the acknowledgement: a user who
/// wants to re-read what they agreed to must find the same statement, not a
/// shorter one (ADR-045).
class PreAuthSecurityNoticePage extends StatelessWidget {
  const PreAuthSecurityNoticePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _AuthenticationScaffold(
      formKey: const ValueKey('preauth-security-notice'),
      title: l10n.securityNoticeTitle,
      subtitle: l10n.authSecurityNoticeMessage,
      leading: AppIconButton(
        icon: AppIcons.back,
        semanticLabel: l10n.authBackAction,
        kind: AppButtonKind.ghost,
        onPressed: () => context.pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SecurityNoticeSections(),
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            label: l10n.authBackAction,
            kind: AppButtonKind.outline,
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }
}

class _AuthenticationScaffold extends StatelessWidget {
  const _AuthenticationScaffold({
    required this.formKey,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
  });

  final Key formKey;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widthClass = AppBreakpoints.of(constraints.maxWidth);
          final form = Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.x6),
              child: ConstrainedBox(
                key: formKey,
                constraints: const BoxConstraints(maxWidth: 480),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.tokens.colors.surface,
                    borderRadius: AppRadii.card,
                    border: Border.all(color: context.tokens.colors.border),
                    boxShadow: AppElevation.level1,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(
                      widthClass == AppWidthClass.narrow
                          ? AppSpacing.x6
                          : AppSpacing.x8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (leading != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: leading,
                          ),
                        const _AuthenticationMark(),
                        const SizedBox(height: AppSpacing.x4),
                        Text(
                          title,
                          style: context.tokens.typography.title,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          subtitle,
                          style: context.tokens.typography.body.copyWith(
                            color: context.tokens.colors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.x8),
                        child,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          if (widthClass != AppWidthClass.wide) {
            return form;
          }
          return Row(
            children: [
              Expanded(
                child: ColoredBox(
                  color: context.tokens.colors.accentSoft,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.x12),
                      child: Text(
                        AppLocalizations.of(context).appTitle,
                        style: context.tokens.typography.title,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(flex: 2, child: form),
            ],
          );
        },
      ),
    ),
  );
}

class _AuthenticationMark extends StatelessWidget {
  const _AuthenticationMark();

  @override
  Widget build(BuildContext context) => Center(
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.tokens.colors.accentSoft,
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 64,
          child: Center(
            child: Text('CP', style: context.tokens.typography.section),
          ),
        ),
      ),
    ),
  );
}

class _AuthenticationNotice extends StatelessWidget {
  const _AuthenticationNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceRaised,
        borderRadius: AppRadii.compact,
        border: Border.all(color: context.tokens.colors.danger),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Text(
          message,
          style: context.tokens.typography.body.copyWith(
            color: context.tokens.colors.danger,
          ),
        ),
      ),
    ),
  );
}

String _localizedMessage(
  AppLocalizations l10n,
  AuthenticationMessage message,
) => switch (message) {
  AuthenticationMessage.invalidCredentials =>
    l10n.authInvalidCredentialsMessage,
  AuthenticationMessage.accountInactive => l10n.authInactiveAccountMessage,
  AuthenticationMessage.usernameTaken => l10n.authUsernameTakenMessage,
  AuthenticationMessage.rateLimited => l10n.authRateLimitedMessage,
  AuthenticationMessage.offline => l10n.authOfflineMessage,
  AuthenticationMessage.malformedResponse => l10n.authMalformedResponseMessage,
  AuthenticationMessage.invalidInput => l10n.authInvalidInputMessage,
  AuthenticationMessage.sessionExpired => l10n.authSessionExpiredMessage,
  AuthenticationMessage.revoked => l10n.authRevokedMessage,
  AuthenticationMessage.storageUnavailable =>
    l10n.authStorageUnavailableMessage,
  AuthenticationMessage.generic => l10n.authGenericErrorMessage,
};
