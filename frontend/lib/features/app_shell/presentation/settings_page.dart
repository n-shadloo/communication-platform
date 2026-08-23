import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/notifications/presentation/notification_settings_entry.dart';
import 'package:communication_platform/features/synchronization/presentation/sustained_delivery_page.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsDestination)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.x4),
        children: [
          _SettingsEntry(
            icon: AppIcons.devices,
            title: l10n.settingsLinkedDevicesTitle,
            summary: l10n.settingsLinkedDevicesSummary,
            onTap: () => context.go('/settings/linked-devices'),
          ),
          // The security notice is acknowledged once, during enrollment, and is
          // never shown again on a timer. It therefore has to stay reachable on
          // demand, or the one statement a user agreed to becomes unreadable
          // after the moment they agreed to it (ADR-045).
          _SettingsEntry(
            entryKey: const ValueKey('settings-security-notice'),
            icon: AppIcons.security,
            title: l10n.authSecurityNoticeAction,
            onTap: () => context.push('/security-notice'),
          ),
          // What the operating system will and will not do about an arriving
          // message, read from the operating system rather than from what this
          // application would prefer to be true.
          const NotificationSettingsEntry(),
          // And whether a message can arrive at all while the application is
          // closed. Off until the user opens this and turns it on, which is why
          // it is a row here rather than a prompt anywhere else.
          const SustainedDeliverySettingsEntry(),
          _SettingsEntry(
            icon: AppIcons.settings,
            title: l10n.settingsAppearanceTitle,
            onTap: () => context.go('/settings/appearance'),
          ),
        ],
      ),
    );
  }
}

final class _SettingsEntry extends StatelessWidget {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.summary,
    this.entryKey,
  });

  final AppIconData icon;
  final String title;
  final String? summary;
  final VoidCallback onTap;
  final Key? entryKey;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: entryKey,
      leading: AppIcon(icon, decorative: true),
      title: Text(title),
      subtitle: summary == null ? null : Text(summary!),
      // `AppIcons.forward` mirrors in RTL; a raw chevron does not, and this
      // page is one of the two the product ships in Persian.
      trailing: AppIcon(AppIcons.forward, decorative: true),
      onTap: onTap,
    ),
  );
}
