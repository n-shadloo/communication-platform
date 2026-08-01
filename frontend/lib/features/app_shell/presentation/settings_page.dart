import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(AppSpacing.x4),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.devices),
            title: const Text('Linked Devices'),
            subtitle: const Text(
              'Review, rename, or revoke devices on this account',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/linked-devices'),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Appearance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/appearance'),
          ),
        ),
      ],
    ),
  );
}
