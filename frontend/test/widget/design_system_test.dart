import 'dart:async';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('directional icons mirror in RTL and universal icons do not', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [AppIcon(AppIcons.back), AppIcon(AppIcons.search)],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('app-icon-back-ltr')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-search-ltr')), findsOneWidget);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [AppIcon(AppIcons.back), AppIcon(AppIcons.search)],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('app-icon-back-rtl')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-icon-search-ltr')), findsOneWidget);
  });

  testWidgets(
    'icon-only controls expose labels, disabled state, and 48px target',
    (tester) async {
      await tester.pumpWidget(
        _Harness(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: AppIcons.search,
                semanticLabel: 'Search locally',
                onPressed: () {},
              ),
              const AppIconButton(
                icon: AppIcons.retry,
                semanticLabel: 'Retry',
                onPressed: null,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Search locally'), findsOneWidget);
      expect(find.bySemanticsLabel('Search locally'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry'), findsOneWidget);
      for (final widget in tester.widgetList<AppIconButton>(
        find.byType(AppIconButton),
      )) {
        expect(
          tester.getSize(find.byWidget(widget)).width,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byWidget(widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
    },
  );

  testWidgets('dialog closure restores focus to the invoking control', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _Harness(
        child: Builder(
          builder: (context) => AppButton(
            label: 'Open dialog',
            focusNode: focusNode,
            onPressed: () {
              unawaited(
                showAppDialog<void>(
                  context: context,
                  title: 'Confirm action',
                  body: 'Structural dialog content.',
                  actions: [
                    AppButton(
                      label: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm action'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('sheet wrapper exposes a named modal route', (tester) async {
    await tester.pumpWidget(
      _Harness(
        child: Builder(
          builder: (context) => AppButton(
            label: 'Open sheet',
            onPressed: () {
              unawaited(
                showAppSheet<void>(
                  context: context,
                  semanticLabel: 'Attachment options',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Local attachment choices'),
                      AppButton(
                        label: 'Close sheet',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Local attachment choices'), findsOneWidget);
    expect(find.bySemanticsLabel('Attachment options'), findsWidgets);
    await tester.tap(find.text('Close sheet'));
    await tester.pumpAndSettle();
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) =>
        AppDesignSystem(child: child ?? const SizedBox.shrink()),
    home: Scaffold(body: Center(child: child)),
  );
}
