import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('development app visibly renders the non-shipping shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CommunicationPlatformApp(
        environment: AppEnvironment.development,
        locale: Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Development configuration'), findsOneWidget);
    expect(
      find.text('Structural placeholder — not for shipping'),
      findsWidgets,
    );
    expect(find.text('Chats structure'), findsOneWidget);
    expect(find.text('Flutter foundation is ready'), findsNothing);
  });

  testWidgets(
    'Persian localization establishes right-to-left shell direction',
    (tester) async {
      await tester.pumpWidget(
        const CommunicationPlatformApp(
          environment: AppEnvironment.production,
          locale: Locale('fa'),
        ),
      );
      await tester.pumpAndSettle();

      final directionality = tester.widget<Directionality>(
        find.byType(Directionality).first,
      );
      expect(directionality.textDirection, TextDirection.rtl);
      expect(find.text('ساختار گفت‌وگوها'), findsOneWidget);
      expect(find.text('پیکربندی توسعه'), findsNothing);
    },
  );
}
