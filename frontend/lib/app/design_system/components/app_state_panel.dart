import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/app/design_system/components/app_button.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

enum AppStateKind { loading, empty, error }

class AppStatePanel extends StatelessWidget {
  const AppStatePanel.loading({required this.title, this.message, super.key})
    : kind = AppStateKind.loading,
      actionLabel = null,
      onAction = null;

  const AppStatePanel.empty({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : kind = AppStateKind.empty;

  const AppStatePanel.error({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : kind = AppStateKind.error;

  final AppStateKind kind;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      AppStateKind.loading => null,
      AppStateKind.empty => AppIcons.empty,
      AppStateKind.error => AppIcons.error,
    };
    final color = kind == AppStateKind.error
        ? context.tokens.colors.danger
        : context.tokens.colors.textMuted;

    return Semantics(
      container: true,
      liveRegion: kind != AppStateKind.empty,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.x6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (kind == AppStateKind.loading)
                        FCircularProgress(
                          size: FCircularProgressSizeVariant.xl,
                          semanticsLabel: title,
                        )
                      else
                        AppIcon(icon!, color: color, size: 32),
                      const SizedBox(height: AppSpacing.x4),
                      Text(
                        title,
                        style: context.tokens.typography.section,
                        textAlign: TextAlign.center,
                      ),
                      if (message != null) ...[
                        const SizedBox(height: AppSpacing.x2),
                        Text(
                          message!,
                          style: context.tokens.typography.body.copyWith(
                            color: context.tokens.colors.textMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: AppSpacing.x6),
                        AppButton(
                          label: actionLabel!,
                          onPressed: onAction,
                          kind: kind == AppStateKind.error
                              ? AppButtonKind.outline
                              : AppButtonKind.primary,
                          leading: kind == AppStateKind.error
                              ? AppIcons.retry
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
