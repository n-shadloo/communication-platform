import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';

/// One tappable row in a settings list.
///
/// Shared rather than repeated so that every settings surface has the same
/// target size, the same screen-reader shape and the same directional chevron.
/// `AppIcons.forward` mirrors in right-to-left; a raw chevron does not, and
/// half of this product's audience reads right to left.
final class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.summary,
    this.trailingText,
    this.danger = false,
    this.entryKey,
    super.key,
  });

  final AppIconData icon;
  final String title;
  final String? summary;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool danger;
  final Key? entryKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final foreground = danger ? colors.danger : null;
    return Card(
      child: ListTile(
        key: entryKey,
        enabled: onTap != null,
        leading: AppIcon(icon, decorative: true, color: foreground),
        title: Text(title, style: TextStyle(color: foreground)),
        subtitle: summary == null ? null : Text(summary!),
        trailing: trailingText != null
            ? Text(
                trailingText!,
                style: context.tokens.typography.label.copyWith(
                  color: colors.textMuted,
                ),
              )
            : AppIcon(AppIcons.forward, decorative: true, color: foreground),
        onTap: onTap,
      ),
    );
  }
}

/// A heading above a group of rows.
final class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.x2,
      AppSpacing.x6,
      AppSpacing.x2,
      AppSpacing.x2,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: context.tokens.typography.section.copyWith(
          color: context.tokens.colors.textMuted,
        ),
      ),
    ),
  );
}

/// A short explanatory paragraph inside a settings surface.
final class SettingsNote extends StatelessWidget {
  const SettingsNote(this.text, {this.emphasis = false, super.key});

  final String text;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      child: Text(
        text,
        style: context.tokens.typography.compact.copyWith(
          color: emphasis ? colors.warning : colors.textMuted,
        ),
      ),
    );
  }
}

/// A single-choice row, used by Appearance for theme and language.
///
/// A radio rather than a switch: both settings have three values, one of which
/// is "follow the phone", and a switch cannot say that.
final class SettingsChoiceRow<T> extends StatelessWidget {
  const SettingsChoiceRow({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
    this.rowKey,
    super.key,
  });

  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onSelected;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          key: rowKey,
          onTap: () => onSelected(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppFocus.minimumTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x2,
                vertical: AppSpacing.x2,
              ),
              child: Row(
                children: [
                  // The mark carries the state in shape as well as colour, so
                  // it survives a high-contrast or colour-blind reading.
                  AppIcon(
                    selected ? AppIcons.accepted : AppIcons.empty,
                    color: selected
                        ? context.tokens.colors.accent
                        : context.tokens.colors.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Text(
                      label,
                      style: context.tokens.typography.body.copyWith(
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
