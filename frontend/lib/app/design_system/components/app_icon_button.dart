import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/app/design_system/components/app_button.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

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
