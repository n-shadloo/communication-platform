import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';

/// The bordered status banner the contact surfaces raise.
///
/// Shared rather than repeated so that an offline cache, a blocked contact, a
/// stand-in profile transport and a safety-number state all announce
/// themselves with the same shape, and so that a danger banner is always a
/// live region a screen reader reads without being asked.
class Notice extends StatelessWidget {
  const Notice({required this.kind, required this.message, super.key});

  final AppStatusKind kind;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: kind == AppStatusKind.danger,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceRaised,
        borderRadius: AppRadii.card,
        border: Border.all(color: context.tokens.colors.border),
      ),
      child: AppStatusBadge(kind: kind, label: message),
    ),
  );
}

/// One tappable action in a contact list.
///
/// Shared by the new-contact entry points and the contact profile so that
/// every action has the same target size, and so that a withheld action reads
/// as disabled with a reason rather than being hidden.
class ActionRow extends StatelessWidget {
  const ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final String label;
  final AppIconData icon;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 56,
    leading: AppIcon(icon),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    enabled: onTap != null,
    onTap: onTap,
  );
}
