import 'dart:math' as math;

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

/// Dismisses the sheet or dialog that [showAppSheet] or [showAppDialog] pushed.
///
/// Both push onto the root navigator, so the dismissal has to leave by the same
/// door. A bare `Navigator.pop(context)` resolves to the *nearest* navigator
/// instead, and a call site that built the modal's contents is almost always
/// sitting inside a shell branch — so the bare form pops the page underneath and
/// leaves the modal standing over whatever it lands on, with every button in it
/// now wired to a widget that is no longer mounted.
///
/// Safe to call from inside the modal as well: the root navigator is the
/// nearest one from there too.
void popAppModal<T extends Object?>(BuildContext context, [T? result]) =>
    Navigator.of(context, rootNavigator: true).pop<T>(result);

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

/// A sheet with a second surface floating above it, anchored to the thing the
/// sheet is about.
///
/// [showAppSheet] cannot express this. Its content is laid out inside the sheet,
/// at the bottom of the screen, so a panel built there cannot sit beside the row
/// the user pressed. The obvious alternative - an `OverlayEntry` above the sheet
/// route - puts the panel outside the route, where a modal route's focus scope
/// cannot reach it and a screen reader does not traverse it, which would fail
/// two of the accessibility rules in `responsive-ui.md`. So both surfaces live
/// in one route: the sheet keeps the bottom, and [anchored] is positioned in the
/// space above it, as close to [anchor] as it fits.
///
/// [anchor] is in global coordinates and may be null, which parks [anchored]
/// directly above the sheet. Dismissal is the barrier, the back gesture, or
/// [popAppModal] - the same three doors as [showAppSheet]. It has no
/// drag-to-dismiss, which the Forui sheet does.
Future<T?> showAppAnchoredSheet<T>({
  required BuildContext context,
  required String semanticLabel,
  required Widget child,
  required Widget anchored,
  Rect? anchor,
  bool dismissible = true,
}) {
  final colors = context.tokens.colors;
  final minimumTop = MediaQuery.paddingOf(context).top + AppSpacing.x2;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: semanticLabel,
    barrierColor: colors.scrim,
    transitionDuration: AppMotion.effective(context, AppMotion.route),
    pageBuilder: (context, animation, secondaryAnimation) => Semantics(
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Column(
        children: [
          Expanded(
            child: CustomSingleChildLayout(
              delegate: _AnchoredAboveLayout(
                anchor: anchor,
                gap: AppSpacing.x2,
                minimumTop: minimumTop,
              ),
              child: anchored,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x6),
                child: child,
              ),
            ),
          ),
        ],
      ),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = animation.drive(CurveTween(curve: AppMotion.enter));
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Places a child just above [anchor], clamped into the space it is given.
///
/// The layout region is the part of the screen the sheet does not occupy, and
/// it starts at the top of the screen, so the global coordinates [anchor]
/// carries need no translation. A message near the bottom of the timeline
/// therefore ends up with its panel resting on the sheet rather than behind it.
class _AnchoredAboveLayout extends SingleChildLayoutDelegate {
  const _AnchoredAboveLayout({
    required this.anchor,
    required this.gap,
    required this.minimumTop,
  });

  final Rect? anchor;
  final double gap;
  final double minimumTop;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final horizontal = math.max(0, size.width - childSize.width) / 2;
    final lowest = math.max(0.0, size.height - childSize.height);
    final highest = math.min(minimumTop, lowest);
    final preferred = anchor == null
        ? lowest
        : anchor!.top - childSize.height - gap;
    return Offset(horizontal, preferred.clamp(highest, lowest));
  }

  @override
  bool shouldRelayout(_AnchoredAboveLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.gap != gap ||
      oldDelegate.minimumTop != minimumTop;
}

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
