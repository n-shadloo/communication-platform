import 'dart:typed_data';

import 'package:communication_platform/app/dependencies/linked_device_providers.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/features/devices/domain/linked_device_model.dart';
import 'package:communication_platform/features/devices/presentation/history_transfer_status.dart';
import 'package:communication_platform/features/devices/presentation/linked_devices_page.dart';
import 'package:communication_platform/features/synchronization/domain/history_transfer_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'lists encrypted labels and requires explicit rename and revoke actions',
    (tester) async {
      var refreshes = 0;
      (String, String)? relabeled;
      String? revoked;
      final devices = [
        LinkedDevice(
          deviceId: '10000000-0000-4000-8000-000000000001',
          label: 'Pixel',
          labelState: LinkedDeviceLabelState.available,
          createdDate: DateTime.utc(2026, 1, 1),
          lastActiveDate: DateTime.utc(2026, 8, 1),
          thisDevice: true,
          encryptedLabel: Uint8List(256),
        ),
        LinkedDevice(
          deviceId: '10000000-0000-4000-8000-000000000002',
          label: 'Desktop',
          labelState: LinkedDeviceLabelState.available,
          createdDate: DateTime.utc(2026, 2, 1),
          lastActiveDate: DateTime.utc(2026, 7, 31),
          thisDevice: false,
          encryptedLabel: Uint8List(256),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            linkedDevicesProvider.overrideWith((ref) => Stream.value(devices)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: AppDesignSystem(
              child: LinkedDevicesPage(
                onRefresh: () async => refreshes += 1,
                onRelabel: (deviceId, label) async {
                  relabeled = (deviceId, label);
                },
                onRevoke: (deviceId) async => revoked = deviceId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(refreshes, 1);
      expect(find.text('Labels are encrypted locally'), findsOneWidget);
      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('Current device'), findsOneWidget);
      expect(find.text('Desktop'), findsOneWidget);
      expect(find.text('Last active: 2026-07-31'), findsOneWidget);

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(refreshes, 2);

      final menus = find.byType(PopupMenuButton<String>);
      await tester.tap(menus.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename').last);
      await tester.pumpAndSettle();
      expect(find.text('Rename device'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Workstation');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(relabeled, (
        '10000000-0000-4000-8000-000000000002',
        'Workstation',
      ));

      await tester.tap(menus.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(find.text('Remove device?'), findsOneWidget);
      expect(
        find.textContaining('requires a signed device-log change'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(revoked, '10000000-0000-4000-8000-000000000002');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history recovery states never imply server-side restoration', (
    tester,
  ) async {
    const expected = <HistoryTransferState, String>{
      HistoryTransferState.identityRecovered:
          'Message history has not been restored.',
      HistoryTransferState.waitingForSource: 'Keep an authorized device online',
      HistoryTransferState.transferring: 'directly between your devices',
      HistoryTransferState.partialTransfer: 'only held part of your history',
      HistoryTransferState.noSource: 'The server has no history copy',
      HistoryTransferState.groupReinviteRequired: 'fresh group epoch',
      HistoryTransferState.queueGapRecovery: 'recover before setup is complete',
      HistoryTransferState.done: 'Available local history has been stored',
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppDesignSystem(
            child: Scaffold(body: HistoryTransferStatusView(state: entry.key)),
          ),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
    }
  });
}
