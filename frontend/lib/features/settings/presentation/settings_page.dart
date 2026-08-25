import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/features/notifications/presentation/notification_settings_entry.dart';
import 'package:communication_platform/features/settings/presentation/settings_components.dart';
import 'package:communication_platform/features/synchronization/presentation/sustained_delivery_page.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings home: the account, the devices, the security surfaces, what the
/// operating system will do about a message, and the two client-only display
/// choices.
///
/// Order follows §15 of the UI specification, which puts the things a person
/// came here to change above the things they came here to read. Log out is last
/// and is the only destructive row, so it is never adjacent to something a
/// thumb was already reaching for.
final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('settings-screen'),
      appBar: AppBar(title: Text(l10n.settingsDestination)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppContentWidths.readable,
          ),
          child: ListView(
            key: const PageStorageKey('settings-list'),
            padding: const EdgeInsets.all(AppSpacing.x4),
            children: [
              const _ProfileHeader(),
              SettingsEntry(
                entryKey: const ValueKey('settings-saved-messages'),
                icon: AppIcons.saved,
                title: l10n.savedMessagesTitle,
                summary: l10n.settingsSavedMessagesSummary,
                onTap: () => context.push('/saved-messages'),
              ),
              SettingsEntry(
                entryKey: const ValueKey('settings-linked-devices'),
                icon: AppIcons.devices,
                title: l10n.settingsLinkedDevicesTitle,
                summary: l10n.settingsLinkedDevicesSummary,
                onTap: () => context.go('/settings/linked-devices'),
              ),
              SettingsEntry(
                entryKey: const ValueKey('settings-security'),
                icon: AppIcons.security,
                title: l10n.settingsSecurityTitle,
                summary: l10n.settingsSecuritySummary,
                onTap: () => context.go('/settings/security'),
              ),
              // What the operating system will and will not do about an
              // arriving message, read from the operating system rather than
              // from what this application would prefer to be true.
              const NotificationSettingsEntry(),
              // And whether a message can arrive at all while the app is
              // closed. Off until the user opens this and turns it on, which is
              // why it is a row here rather than a prompt anywhere else.
              const SustainedDeliverySettingsEntry(),
              SettingsEntry(
                entryKey: const ValueKey('settings-appearance'),
                icon: AppIcons.settings,
                title: l10n.settingsAppearanceTitle,
                summary: l10n.settingsAppearanceSummary,
                onTap: () => context.go('/settings/appearance'),
              ),
              // The security notice is acknowledged once, during enrollment,
              // and is never shown again on a timer. It therefore has to stay
              // reachable on demand, or the one statement a user agreed to
              // becomes unreadable after the moment they agreed to it
              // (ADR-045).
              SettingsEntry(
                entryKey: const ValueKey('settings-security-notice'),
                icon: AppIcons.info,
                title: l10n.authSecurityNoticeAction,
                onTap: () => context.push('/security-notice'),
              ),
              SettingsEntry(
                entryKey: const ValueKey('settings-about'),
                icon: AppIcons.info,
                title: l10n.settingsAboutTitle,
                summary: l10n.settingsAboutSummary,
                onTap: () => context.go('/settings/about'),
              ),
              const SizedBox(height: AppSpacing.x4),
              const _LogOutEntry(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The account header, when this composition has an authenticated session.
///
/// A route or shell harness renders this page without the production
/// container. It then shows the row without a name rather than failing, for the
/// same reason the notification row does: a settings screen may not break over
/// a dependency it only needs in order to be more informative.
final class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context);
    } on StateError {
      return const _ProfileRow(username: null);
    }
    return const _LiveProfileHeader();
  }
}

final class _LiveProfileHeader extends ConsumerWidget {
  const _LiveProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? username;
    try {
      username = ref.watch(authenticationControllerProvider).username;
    } on Object {
      username = null;
    }
    return _ProfileRow(username: username);
  }
}

final class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.username});

  final String? username;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = username;
    return Card(
      child: ListTile(
        key: const ValueKey('settings-profile'),
        leading: name == null
            ? const AppIcon(AppIcons.settings, decorative: true)
            : ContactAvatar(username: name, semanticLabel: name),
        title: Text(
          name == null ? l10n.profileEditTitle : l10n.settingsSignedInAs(name),
        ),
        subtitle: Text(l10n.settingsProfileSummary),
        trailing: const AppIcon(AppIcons.forward, decorative: true),
        onTap: () => context.go('/settings/profile'),
      ),
    );
  }
}

/// Log out, and the dialog that states what it costs.
///
/// Disabled rather than hidden in a composition with no session: a control that
/// disappears reads as a feature that does not exist, and this one does.
final class _LogOutEntry extends StatelessWidget {
  const _LogOutEntry();

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context);
    } on StateError {
      return const _LogOutRow(onLogOut: null);
    }
    return const _LiveLogOutEntry();
  }
}

final class _LiveLogOutEntry extends ConsumerWidget {
  const _LiveLogOutEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    AuthenticationViewState? view;
    try {
      view = ref.watch(authenticationControllerProvider);
    } on Object {
      view = null;
    }
    if (view == null) {
      return const _LogOutRow(onLogOut: null);
    }
    return _LogOutRow(
      onLogOut: view.isBusy
          ? null
          : () => ref.read(authenticationControllerProvider.notifier).logout(),
    );
  }
}

final class _LogOutRow extends StatelessWidget {
  const _LogOutRow({required this.onLogOut});

  final Future<void> Function()? onLogOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logOut = onLogOut;
    return SettingsEntry(
      entryKey: const ValueKey('settings-log-out'),
      icon: AppIcons.close,
      title: l10n.settingsLogOutTitle,
      danger: true,
      onTap: logOut == null ? null : () => _confirm(context, l10n, logOut),
    );
  }

  static Future<void> _confirm(
    BuildContext context,
    AppLocalizations l10n,
    Future<void> Function() logOut,
  ) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: l10n.settingsLogOutConfirmTitle,
      body: l10n.settingsLogOutConfirmBody,
      actions: [
        AppButton(
          label: l10n.settingsCancelAction,
          kind: AppButtonKind.ghost,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: l10n.settingsLogOutConfirmAction,
          kind: AppButtonKind.danger,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    if (confirmed ?? false) {
      await logOut();
    }
  }
}
