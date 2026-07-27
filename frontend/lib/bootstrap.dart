import 'package:communication_platform/app/bootstrap_app.dart';
import 'package:communication_platform/config/app_environment.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void bootstrap(AppEnvironment environment) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: BootstrapApp(environment: environment)));
}
