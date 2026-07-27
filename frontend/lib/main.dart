import 'package:communication_platform/bootstrap.dart';
import 'package:communication_platform/config/app_environment.dart';

/// Defaults local `flutter run` commands to the visibly non-production app.
void main() => bootstrap(AppEnvironment.development);
