import 'package:communication_platform/app/app.dart';
import 'package:communication_platform/app/config/app_configuration.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/authentication_assembly.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/dio_health_reachability_port.dart';
import 'package:communication_platform/features/bootstrap/infrastructure/provisioned_trust_port.dart';
import 'package:communication_platform/features/local_storage/infrastructure/platform/platform_local_storage.dart';
import 'package:communication_platform/features/local_storage/infrastructure/protected_storage_bootstrap_adapter.dart';
import 'package:communication_platform/shared/infrastructure/time/system_time_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = kIsWeb ? BootstrapPlatform.web : BootstrapPlatform.android;
  final localStorageRuntime = createPlatformLocalStorageRuntime();
  final configurationPort = CompileTimeBootstrapConfiguration(
    environment: environment,
    platform: platform,
  );
  final configurationResult = await configurationPort.load();
  final authentication = switch (configurationResult) {
    ConfigurationLoaded(:final configuration) => AuthenticationAssembly.create(
      serverOrigin: configuration.serverOrigin.uri,
      localStorage: localStorageRuntime,
      timeSource: const SystemTimeSource(),
    ),
    ConfigurationNotProvisioned() => null,
  };
  final flow = BootstrapFlow(
    configuration: _ResolvedBootstrapConfiguration(configurationResult),
    storage: ProtectedStorageBootstrapAdapter(localStorageRuntime),
    trust: const ProvisionedTrustPort(),
    health: DioHealthReachabilityPort(),
    platform: platform,
  );
  runApp(
    ProviderScope(
      overrides: [
        if (authentication != null)
          authenticationUseCasesProvider.overrideWithValue(
            authentication.useCases,
          ),
        localStorageRuntimeProvider.overrideWith((ref) {
          ref.onDispose(localStorageRuntime.close);
          return localStorageRuntime;
        }),
      ],
      child: CommunicationPlatformApp(
        environment: environment,
        bootstrapFlow: flow,
        bootstrapPlatform: platform,
        authenticationEnabled: authentication != null,
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
