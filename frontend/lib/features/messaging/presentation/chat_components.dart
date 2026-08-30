import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';

class ChatMenuRow extends StatelessWidget {
  const ChatMenuRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: AppFocus.minimumTarget,
    leading: AppIcon(
      icon,
      color: danger
          ? context.tokens.colors.danger
          : context.tokens.colors.textPrimary,
    ),
    title: Text(
      label,
      style: context.tokens.typography.body.copyWith(
        color: danger
            ? context.tokens.colors.danger
            : context.tokens.colors.textPrimary,
      ),
    ),
    onTap: onTap,
  );
}

String chatShortIdentity(String value) =>
    value.length <= 12 ? value : '${value.substring(0, 8)}…';
