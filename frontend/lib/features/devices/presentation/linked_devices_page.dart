import 'package:communication_platform/app/dependencies/linked_device_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final class LinkedDevicesPage extends ConsumerStatefulWidget {
  const LinkedDevicesPage({
    this.onRefresh,
    this.onRelabel,
    this.onRevoke,
    super.key,
  });

  final Future<void> Function()? onRefresh;
  final Future<void> Function(String deviceId, String label)? onRelabel;
  final Future<void> Function(String deviceId)? onRevoke;
  @override
  ConsumerState<LinkedDevicesPage> createState() => _LinkedDevicesPageState();
}

final class _LinkedDevicesPageState extends ConsumerState<LinkedDevicesPage> {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    if (widget.onRefresh case final callback?) {
      await callback();
    } else {
      final manager = await ref.read(linkedDeviceManagerProvider.future);
      await manager.refresh();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _relabel(LinkedDevice device) async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDeviceDialog(initial: device.label ?? ''),
    );
    if (label == null || label.isEmpty) return;
    if (widget.onRelabel case final callback?) {
      await callback(device.deviceId, label);
    } else {
      final manager = await ref.read(linkedDeviceManagerProvider.future);
      await manager.relabel(deviceId: device.deviceId, label: label);
    }
  }

  Future<void> _revoke(LinkedDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          device.thisDevice ? 'Remove this device?' : 'Remove device?',
        ),
        content: const Text(
          'This action requires a signed device-log change and cannot be undone from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.onRevoke case final callback?) {
      await callback(device.deviceId);
    } else {
      final manager = await ref.read(linkedDeviceManagerProvider.future);
      await manager.revoke(deviceId: device.deviceId);
    }
    if (device.thisDevice && mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(linkedDevicesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: devices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Device list unavailable: $error')),
        data: (rows) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.x4),
            children: [
              const AppStatusBadge(
                kind: AppStatusKind.information,
                label: 'Labels are encrypted locally',
              ),
              const SizedBox(height: AppSpacing.x4),
              if (rows.isEmpty) const Text('No linked devices'),
              for (final row in rows)
                Card(
                  child: ListTile(
                    leading: Icon(
                      row.thisDevice
                          ? Icons.phone_android
                          : Icons.devices_other,
                    ),
                    title: Text(
                      row.label ??
                          (row.thisDevice ? 'This device' : 'Unnamed device'),
                    ),
                    subtitle: Text(
                      row.thisDevice
                          ? 'Current device'
                          : 'Last active: ${row.lastActiveDate?.toLocal().toString().split(' ').first ?? 'Unknown'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          action == 'rename' ? _relabel(row) : _revoke(row),
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.x4),
              AppButton(
                label: 'Add device',
                leading: AppIcons.add,
                onPressed: () => context.go('/devices/enroll'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RenameDeviceDialog extends StatefulWidget {
  const _RenameDeviceDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

final class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename device'),
    content: TextField(controller: controller, autofocus: true, maxLength: 64),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
