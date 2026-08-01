import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class AttachmentSheet extends StatelessWidget {
  const AttachmentSheet({this.descriptor, this.onCancelled, super.key});

  final EncryptedAttachmentDescriptor? descriptor;
  final VoidCallback? onCancelled;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = context.tokens.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              descriptor == null
                  ? strings.chatAttachAction
                  : descriptor!.displayName,
              style: context.tokens.typography.title,
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              descriptor == null
                  ? strings.attachmentChoosePrompt
                  : strings.attachmentDetails(
                      descriptor!.mimeType,
                      descriptor!.plaintextSize,
                    ),
              style: context.tokens.typography.compact.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.x2),
            if (descriptor == null) ...[
              _AttachmentChoice(
                icon: AppIcons.attach,
                label: strings.attachmentPhotoOption,
                onPressed: onCancelled,
              ),
              _AttachmentChoice(
                icon: AppIcons.attach,
                label: strings.attachmentFileOption,
                onPressed: onCancelled,
              ),
              _AttachmentChoice(
                icon: AppIcons.attach,
                label: strings.attachmentCameraOption,
                onPressed: onCancelled,
              ),
            ] else
              AppButton(
                label: strings.chatAttachmentsUnavailable,
                kind: AppButtonKind.outline,
                onPressed: onCancelled,
              ),
            const SizedBox(height: AppSpacing.x1),
            AppButton(
              label: strings.chatCancelAction,
              kind: AppButtonKind.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

final class _AttachmentChoice extends StatelessWidget {
  const _AttachmentChoice({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: ListTile(
      leading: AppIcon(icon, decorative: true),
      title: Text(label),
      onTap: onPressed,
    ),
  );
}
