import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';

enum AppStatusKind { neutral, information, success, warning, danger }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({required this.kind, required this.label, super.key});

  final AppStatusKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final (color, icon) = switch (kind) {
      AppStatusKind.neutral => (colors.textMuted, AppIcons.info),
      AppStatusKind.information => (colors.accent, AppIcons.info),
      AppStatusKind.success => (colors.success, AppIcons.success),
      AppStatusKind.warning => (colors.warning, AppIcons.warning),
      AppStatusKind.danger => (colors.danger, AppIcons.error),
    };

    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: AppRadii.pill,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, color: color, size: 16),
              const SizedBox(width: AppSpacing.x1),
              Flexible(
                child: Text(
                  label,
                  style: context.tokens.typography.label.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
