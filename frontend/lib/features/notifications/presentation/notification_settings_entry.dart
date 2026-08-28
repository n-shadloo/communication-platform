import 'package:communication_platform/app/dependencies/message_alerts.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the operating system currently says about alerts.
///
/// It deliberately touches no database. A build with no alert implementation
/// behind it - a host test, a future Web target - resolves to
/// [MessageAlertAuthorization.unavailable] and the row says so, rather than a
/// settings screen failing over a storage dependency it does not need.
final messageAlertAuthorizationProvider =
    FutureProvider.autoDispose<MessageAlertAuthorization>((ref) async {
      final state = await ref
          .watch(messageAlertPresenterProvider)
          .platformState();
      return state?.authorization ?? MessageAlertAuthorization.unavailable;
    });

/// The Settings row for alerts.
///
/// Route and app-shell harnesses render this surface without the production
/// container, so the row states what it can see rather than failing: with no
/// composition there is no alert implementation, and "not available" is the
/// truthful reading of that, not a fallback pretending to be one.
class NotificationSettingsEntry extends StatelessWidget {
  const NotificationSettingsEntry({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context);
    } on StateError {
      return const _NotificationRow(
        authorization: MessageAlertAuthorization.unavailable,
      );
    }
    return const _LiveNotificationSettingsEntry();
  }
}

class _LiveNotificationSettingsEntry extends ConsumerStatefulWidget {
  const _LiveNotificationSettingsEntry();

  @override
  ConsumerState<_LiveNotificationSettingsEntry> createState() =>
      _LiveNotificationSettingsEntryState();
}

class _LiveNotificationSettingsEntryState
    extends ConsumerState<_LiveNotificationSettingsEntry>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The two things that can change the answer - the system permission prompt
  /// and the operating system settings screen - both take the user out of this
  /// application and bring them back, so returning is when to re-read it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(messageAlertAuthorizationProvider);
    }
  }

  @override
  Widget build(BuildContext context) => _NotificationRow(
    authorization:
        ref.watch(messageAlertAuthorizationProvider).value ??
        MessageAlertAuthorization.unavailable,
    onTurnOn: _busy ? null : _turnOn,
  );

  /// One action for every off state.
  ///
  /// Android shows its own prompt while it still will, and stops showing it
  /// after a second refusal without telling the application which case it is
  /// in. Asking first and falling through to the operating system settings when
  /// the answer did not change means one tap always ends somewhere the user can
  /// actually change the outcome, and never on a button that silently does
  /// nothing.
  Future<void> _turnOn() async {
    setState(() => _busy = true);
    try {
      final presenter = ref.read(messageAlertPresenterProvider);
      final state = await presenter.requestPermission();
      if (state?.authorization != MessageAlertAuthorization.granted) {
        await presenter.openSystemSettings();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(messageAlertAuthorizationProvider);
      }
    }
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.authorization, this.onTurnOn});

  final MessageAlertAuthorization authorization;
  final VoidCallback? onTurnOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = switch (authorization) {
      MessageAlertAuthorization.granted => l10n.settingsNotificationsOn,
      MessageAlertAuthorization.withheld => l10n.settingsNotificationsOff,
      MessageAlertAuthorization.unavailable =>
        l10n.settingsNotificationsUnavailable,
    };
    return Card(
      child: ListTile(
        key: const ValueKey('settings-notifications'),
        leading: const AppIcon(AppIcons.notifications),
        title: Text(l10n.settingsNotificationsTitle),
        subtitle: Text(summary),
        trailing: authorization == MessageAlertAuthorization.withheld
            ? TextButton(
                key: const ValueKey('settings-notifications-turn-on'),
                onPressed: onTurnOn,
                child: Text(l10n.settingsNotificationsTurnOn),
              )
            : null,
      ),
    );
  }
}
