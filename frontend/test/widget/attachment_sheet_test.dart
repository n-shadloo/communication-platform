import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/features/attachments/presentation/attachment_sheet.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('attachment choices are localized and semantically reachable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selections = 0;
    await _pump(tester, AttachmentSheet(onCancelled: () => selections += 1));

    expect(find.text('Choose encrypted media or a file.'), findsOneWidget);
    for (final label in ['Photo or image', 'File', 'Camera']) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    await tester.tap(find.text('File'));
    expect(selections, 1);
    semantics.dispose();
  });

  testWidgets('verified descriptor shows a safe name and bounded details', (
    tester,
  ) async {
    final descriptor = EncryptedAttachmentDescriptor(
      capabilityId: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      key: Uint8List(32),
      header: _header(),
      secretstreamHeader: Uint8List(24),
      encryptedSize: 18,
      bucketSize: 65536,
      plaintextSize: 1,
      displayName: '../photo.jpg',
      mimeType: 'image/jpeg',
      mediaKind: AttachmentMediaKind.image,
      width: 1,
      height: 1,
    );

    await _pump(tester, AttachmentSheet(descriptor: descriptor));

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('image/jpeg · 1 bytes'), findsOneWidget);
    expect(find.text('Open or save verified file'), findsOneWidget);
    expect(find.textContaining('../'), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) =>
        AppDesignSystem(child: child ?? const SizedBox.shrink()),
    home: Scaffold(body: child),
  ),
);

Uint8List _header() {
  final bytes = Uint8List(66);
  bytes.setAll(0, ascii.encode('CPAFV001'));
  bytes[8] = 1;
  final data = ByteData.sublistView(bytes);
  data.setUint32(10, 65536, Endian.big);
  data.setUint64(14, 1, Endian.big);
  data.setUint64(22, 18, Endian.big);
  data.setUint32(30, 65536, Endian.big);
  return bytes;
}
