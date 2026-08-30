import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_scaffold.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    return AuthenticationScaffold(
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
