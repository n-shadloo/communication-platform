import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('development bootstrap renders without template behavior', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CommunicationPlatformApp(
        environment: AppEnvironment.development,
        locale: Locale('en'),
      ),
    );

    expect(find.text('Communication Platform'), findsOneWidget);
    expect(find.text('Development configuration'), findsOneWidget);
    expect(find.text('Flutter foundation is ready'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Persian localization establishes right-to-left direction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CommunicationPlatformApp(
        environment: AppEnvironment.production,
        locale: Locale('fa'),
      ),
    );

    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
    expect(find.text('پایهٔ فلاتر آماده است'), findsOneWidget);
    expect(find.text('پیکربندی توسعه'), findsNothing);
  });
}
