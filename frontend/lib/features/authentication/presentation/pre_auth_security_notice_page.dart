import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_scaffold.dart';
import 'package:communication_platform/features/devices/presentation/security_notice_sections.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    return AuthenticationScaffold(
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
