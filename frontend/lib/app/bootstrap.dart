import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_configuration.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/fail_closed_bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/provisioned_trust_port.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void bootstrap(AppEnvironment environment) {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = kIsWeb ? BootstrapPlatform.web : BootstrapPlatform.android;
  final flow = BootstrapFlow(
    configuration: CompileTimeBootstrapConfiguration(
      environment: environment,
      platform: platform,
    ),
    storage: const PendingProtectedStoragePort(),
    trust: const ProvisionedTrustPort(),
    health: const PendingHealthReachabilityPort(),
    platform: platform,
  );
  runApp(
    ProviderScope(
      child: CommunicationPlatformApp(
        environment: environment,
        bootstrapFlow: flow,
        bootstrapPlatform: platform,
      ),
    ),
  );
}
