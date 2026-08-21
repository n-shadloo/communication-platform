import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/application_runtime.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/dio_health_reachability_port.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/provisioned_trust_port.dart';
import 'package:communication_platform/features/local_storage/infrastructure/protected_storage_bootstrap_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await ApplicationRuntime.create(
    environment,
    platform: kIsWeb ? BootstrapPlatform.web : BootstrapPlatform.android,
  );
  final flow = BootstrapFlow(
    configuration: _ResolvedBootstrapConfiguration(runtime.configuration),
    storage: ProtectedStorageBootstrapAdapter(runtime.localStorage),
    trust: const ProvisionedTrustPort(),
    health: DioHealthReachabilityPort(
      transportSecurity: runtime.transportSecurity,
    ),
    platform: runtime.platform,
  );
  runApp(
    runtime.scope(
      child: CommunicationPlatformApp(
        environment: environment,
        bootstrapFlow: flow,
        bootstrapPlatform: runtime.platform,
        authenticationEnabled: runtime.isAuthenticated,
      ),
    ),
  );
}

final class _ResolvedBootstrapConfiguration
    implements BootstrapConfigurationPort {
  const _ResolvedBootstrapConfiguration(this.result);

  final ConfigurationLoadResult result;

  @override
  Future<ConfigurationLoadResult> load() async => result;
}
