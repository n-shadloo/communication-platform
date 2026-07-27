import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_configuration.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/dio_health_reachability_port.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/provisioned_trust_port.dart';
import 'package:communication_platform/features/local_storage/infrastructure/platform/platform_local_storage.dart';
import 'package:communication_platform/features/local_storage/infrastructure/protected_storage_bootstrap_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void bootstrap(AppEnvironment environment) {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = kIsWeb ? BootstrapPlatform.web : BootstrapPlatform.android;
  final localStorageRuntime = createPlatformLocalStorageRuntime();
  final flow = BootstrapFlow(
    configuration: CompileTimeBootstrapConfiguration(
      environment: environment,
      platform: platform,
    ),
    storage: ProtectedStorageBootstrapAdapter(localStorageRuntime),
    trust: const ProvisionedTrustPort(),
    health: DioHealthReachabilityPort(),
    platform: platform,
  );
  runApp(
    ProviderScope(
      overrides: [
        localStorageRuntimeProvider.overrideWith((ref) {
          ref.onDispose(localStorageRuntime.close);
          return localStorageRuntime;
        }),
      ],
      child: CommunicationPlatformApp(
        environment: environment,
        bootstrapFlow: flow,
        bootstrapPlatform: platform,
      ),
    ),
  );
}
