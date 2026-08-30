import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_scaffold.dart';
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

    return AuthenticationScaffold(
      formKey: const ValueKey('login-screen'),
      title: l10n.authLoginTitle,
      subtitle: l10n.authLoginSubtitle,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.message != null) ...[
              AuthenticationNotice(
                message: authenticationMessageText(l10n, state.message!),
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
