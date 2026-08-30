import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// The shared frame every pre-authentication screen is drawn in.
///
/// Public because Dart privacy is library-scoped: the authentication pages
/// each live in their own file now, so the chrome they share has to be
/// reachable from outside the library that declares it.
class AuthenticationScaffold extends StatelessWidget {
  const AuthenticationScaffold({
    required this.formKey,
    required this.title,
    required this.subtitle,
    required this.child,
    this.leading,
    super.key,
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

/// The single error banner the authentication forms raise.
///
/// A semantic live region rather than plain text, so a screen reader
/// announces a failed attempt instead of leaving the user to hunt for it.
class AuthenticationNotice extends StatelessWidget {
  const AuthenticationNotice({required this.message, super.key});

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

/// Maps an [AuthenticationMessage] onto the localized string shown for it.
String authenticationMessageText(
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
