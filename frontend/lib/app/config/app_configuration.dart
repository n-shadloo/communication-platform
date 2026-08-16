import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

/// Compile-time public provisioning inputs.
///
/// Concrete origins, CA fingerprints, and SPKI pins are supplied by the controlled
/// build environment. They are deliberately absent from source control.
final class AppProvisioningValues {
  const AppProvisioningValues({
    required this.serverOrigin,
    required this.privateCaSha256,
    required this.primarySpkiSha256,
    required this.backupSpkiSha256,
  });

  final String serverOrigin;
  final String privateCaSha256;
  final String primarySpkiSha256;
  final String backupSpkiSha256;
}

/// Locked runtime policy shared by both flavors and asserted independently in tests.
final class AppRuntimePolicy {
  const AppRuntimePolicy._();

  static const lockedDown = AppRuntimePolicy._();

  bool get allowsArbitraryServerSelection => false;
  bool get allowsCertificateBypass => false;
  bool get allowsPublicConnectivityProbes => false;
  bool get allowsRemoteConfiguration => false;
  bool get allowsTelemetry => false;
  bool get allowsThirdPartyRuntimeResources => false;
}

final class CompileTimeBootstrapConfiguration
    implements BootstrapConfigurationPort {
  const CompileTimeBootstrapConfiguration({
    required this.environment,
    required this.platform,
    this.provisioningValues,
  });

  final AppEnvironment environment;
  final BootstrapPlatform platform;
  final AppProvisioningValues? provisioningValues;

  static const _developmentValues = AppProvisioningValues(
    serverOrigin: String.fromEnvironment('DEVELOPMENT_SERVER_ORIGIN'),
    privateCaSha256: String.fromEnvironment('DEVELOPMENT_PRIVATE_CA_SHA256'),
    primarySpkiSha256: String.fromEnvironment(
      'DEVELOPMENT_PRIMARY_SPKI_SHA256',
    ),
    backupSpkiSha256: String.fromEnvironment('DEVELOPMENT_BACKUP_SPKI_SHA256'),
  );

  static const _productionValues = AppProvisioningValues(
    serverOrigin: String.fromEnvironment('PRODUCTION_SERVER_ORIGIN'),
    privateCaSha256: String.fromEnvironment('PRODUCTION_PRIVATE_CA_SHA256'),
    primarySpkiSha256: String.fromEnvironment('PRODUCTION_PRIMARY_SPKI_SHA256'),
    backupSpkiSha256: String.fromEnvironment('PRODUCTION_BACKUP_SPKI_SHA256'),
  );

  static const _betaValues = AppProvisioningValues(
    serverOrigin: String.fromEnvironment('BETA_SERVER_ORIGIN'),
    privateCaSha256: String.fromEnvironment('BETA_PRIVATE_CA_SHA256'),
    primarySpkiSha256: String.fromEnvironment('BETA_PRIMARY_SPKI_SHA256'),
    backupSpkiSha256: String.fromEnvironment('BETA_BACKUP_SPKI_SHA256'),
  );

  AppProvisioningValues get _selectedValues =>
      provisioningValues ??
      switch (environment) {
        AppEnvironment.development => _developmentValues,
        AppEnvironment.beta => _betaValues,
        AppEnvironment.production => _productionValues,
      };

  @override
  Future<ConfigurationLoadResult> load() async {
    final values = _selectedValues;
    if (values.serverOrigin.isEmpty || values.privateCaSha256.isEmpty) {
      return const ConfigurationNotProvisioned(
        ConfigurationFailureKind.missingProvisioning,
      );
    }

    final origin = ServerOrigin.parse(values.serverOrigin);
    if (origin == null) {
      return const ConfigurationNotProvisioned(
        ConfigurationFailureKind.invalidOrigin,
      );
    }
    if (!_isSha256Hex(values.privateCaSha256)) {
      return const ConfigurationNotProvisioned(
        ConfigurationFailureKind.invalidPrivateCaFingerprint,
      );
    }

    final PlatformTrustMaterial trustMaterial;
    switch (platform) {
      case BootstrapPlatform.android:
        if (!_isSha256Pin(values.primarySpkiSha256)) {
          return const ConfigurationNotProvisioned(
            ConfigurationFailureKind.invalidPrimaryPin,
          );
        }
        if (!_isSha256Pin(values.backupSpkiSha256)) {
          return const ConfigurationNotProvisioned(
            ConfigurationFailureKind.invalidBackupPin,
          );
        }
        if (values.primarySpkiSha256 == values.backupSpkiSha256) {
          return const ConfigurationNotProvisioned(
            ConfigurationFailureKind.duplicatePins,
          );
        }
        trustMaterial = AndroidTrustMaterial(
          privateCaSha256: values.privateCaSha256.toLowerCase(),
          primarySpkiSha256: values.primarySpkiSha256,
          backupSpkiSha256: values.backupSpkiSha256,
        );
      case BootstrapPlatform.web:
        trustMaterial = WebTrustMaterial(
          privateCaSha256: values.privateCaSha256.toLowerCase(),
        );
    }

    return ConfigurationLoaded(
      ProvisionedBootstrapConfiguration(
        serverOrigin: origin,
        trustMaterial: trustMaterial,
      ),
    );
  }

  static bool _isSha256Hex(String value) =>
      RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  static bool _isSha256Pin(String value) =>
      RegExp(r'^[A-Za-z0-9+/]{43}=$').hasMatch(value);
}
