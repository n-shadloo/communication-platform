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
