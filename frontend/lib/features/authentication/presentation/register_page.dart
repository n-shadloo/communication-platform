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
        ? authenticationMessageText(l10n, state.message!)
        : null;

    return AuthenticationScaffold(
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
              AuthenticationNotice(message: globalMessage),
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
