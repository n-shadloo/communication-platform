import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

enum AppButtonKind { primary, secondary, danger, outline, ghost }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.leading,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final AppIconData? leading;
  final bool autofocus;
  final FocusNode? focusNode;

  FButtonVariant get _variant => switch (kind) {
    AppButtonKind.primary => FButtonVariant.primary,
    AppButtonKind.secondary => FButtonVariant.secondary,
    AppButtonKind.danger => FButtonVariant.destructive,
    AppButtonKind.outline => FButtonVariant.outline,
    AppButtonKind.ghost => FButtonVariant.ghost,
  };

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: AppFocus.minimumTarget),
    child: FButton(
      onPress: onPressed,
      variant: _variant,
      size: FButtonSizeVariant.lg,
      autofocus: autofocus,
      focusNode: focusNode,
      prefix: leading == null ? null : AppIcon(leading!),
      child: Flexible(child: Text(label, textAlign: TextAlign.center)),
    ),
  );
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.kind = AppButtonKind.outline,
    this.selected = false,
    this.focusNode,
    super.key,
  });

  final AppIconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final bool selected;
  final FocusNode? focusNode;

  FButtonVariant get _variant => switch (kind) {
    AppButtonKind.primary => FButtonVariant.primary,
    AppButtonKind.secondary => FButtonVariant.secondary,
    AppButtonKind.danger => FButtonVariant.destructive,
    AppButtonKind.outline => FButtonVariant.outline,
    AppButtonKind.ghost => FButtonVariant.ghost,
  };

  @override
  Widget build(BuildContext context) => Tooltip(
    message: semanticLabel,
    child: ConstrainedBox(
      constraints: const BoxConstraints.tightFor(
        width: AppFocus.minimumTarget,
        height: AppFocus.minimumTarget,
      ),
      child: FButton.icon(
        onPress: onPressed,
        variant: _variant,
        size: FButtonSizeVariant.lg,
        semanticsLabel: semanticLabel,
        selected: selected,
        focusNode: focusNode,
        child: AppIcon(icon),
      ),
    ),
  );
}

class AppField extends StatelessWidget {
  const AppField({
    required this.label,
    this.controller,
    this.hint,
    this.description,
    this.error,
    this.enabled = true,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction,
    this.keyboardType,
    this.autofillHints,
    this.maxLength,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? description;
  final String? error;
  final bool enabled;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final control = FTextFieldControl.managed(
      controller: controller,
      onChange: onChanged == null ? null : (value) => onChanged!(value.text),
    );
    if (obscureText) {
      return FTextField.password(
        control: control,
        size: FTextFieldSizeVariant.lg,
        label: Text(label),
        hint: hint,
        description: description == null ? null : Text(description!),
        error: error == null ? null : Text(error!),
        enabled: enabled,
        focusNode: focusNode,
        textInputAction: textInputAction ?? TextInputAction.next,
        keyboardType: keyboardType,
        onSubmit: onSubmitted,
        maxLength: maxLength,
        autofillHints: autofillHints ?? const [AutofillHints.password],
      );
    }
    return FTextField(
      control: control,
      size: FTextFieldSizeVariant.lg,
      label: Text(label),
      hint: hint,
      description: description == null ? null : Text(description!),
      error: error == null ? null : Text(error!),
      enabled: enabled,
      focusNode: focusNode,
      textInputAction: textInputAction,
      keyboardType: keyboardType,
      onSubmit: onSubmitted,
      maxLength: maxLength,
      autofillHints: autofillHints,
    );
  }
}

enum AppStatusKind { neutral, information, success, warning, danger }

class AppCheckboxRow extends StatelessWidget {
  const AppCheckboxRow({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value,
    enabled: onChanged != null,
    child: Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged == null
            ? null
            : (next) => onChanged!(next ?? false),
        title: Text(label, style: context.tokens.typography.body),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
      ),
    ),
  );
}

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

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required String body,
  required List<Widget> actions,
  bool dismissible = true,
}) => showFDialog<T>(
  context: context,
  barrierDismissible: dismissible,
  useRootNavigator: true,
  builder: (dialogContext, style, animation) => FDialog(
    animation: animation,
    semanticsLabel: title,
    builder: (context, dialogStyle) => Padding(
      padding: const EdgeInsets.all(AppSpacing.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: context.tokens.typography.section),
          const SizedBox(height: AppSpacing.x3),
          Text(body, style: context.tokens.typography.body),
          const SizedBox(height: AppSpacing.x6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: actions,
          ),
        ],
      ),
    ),
  ),
);

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String semanticLabel,
  required Widget child,
  bool dismissible = true,
}) => showFSheet<T>(
  context: context,
  useRootNavigator: true,
  side: FLayout.btt,
  barrierLabel: semanticLabel,
  barrierDismissible: dismissible,
  useSafeArea: true,
  builder: (context) => Semantics(
    container: true,
    scopesRoute: true,
    namesRoute: true,
    explicitChildNodes: true,
    label: semanticLabel,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: child,
        ),
      ),
    ),
  ),
);

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
