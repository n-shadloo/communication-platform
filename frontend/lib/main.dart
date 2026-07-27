import 'package:communication_platform/app/bootstrap.dart';
import 'package:communication_platform/app/config/app_environment.dart';

/// Defaults local `flutter run` commands to the visibly non-production app.
void main() => bootstrap(AppEnvironment.development);
