import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

final class FakeBootstrapConfigurationPort
    implements BootstrapConfigurationPort {
  FakeBootstrapConfigurationPort(ConfigurationLoadResult result)
    : _results = Queue.of([result]);

  FakeBootstrapConfigurationPort.queued(List<ConfigurationLoadResult> results)
    : _results = Queue.of(results);

  final Queue<ConfigurationLoadResult> _results;
  int calls = 0;

  @override
  Future<ConfigurationLoadResult> load() async {
    calls += 1;
    if (_results.length > 1) {
      return _results.removeFirst();
    }
    return _results.first;
  }
}

final class FakeProtectedStoragePort implements ProtectedStorageBootstrapPort {
  FakeProtectedStoragePort({
    this.availability = ProtectedStorageAvailability.available,
    LocalStateDiscoveryResult? discovery,
  }) : discovery =
           discovery ?? const LocalStateDiscovered(LocalBootstrapState.fresh());

  final ProtectedStorageAvailability availability;
  final LocalStateDiscoveryResult discovery;
  int availabilityCalls = 0;
  int discoveryCalls = 0;

  @override
  Future<ProtectedStorageAvailability> checkAvailability() async {
    availabilityCalls += 1;
    return availability;
  }

  @override
  Future<LocalStateDiscoveryResult> discoverLocalState() async {
    discoveryCalls += 1;
    return discovery;
  }
}

final class FakePlatformTrustPort implements PlatformTrustPort {
  FakePlatformTrustPort([this.result = const TrustValidated()]);

  final TrustValidationResult result;
  int calls = 0;
  ProvisionedBootstrapConfiguration? checkedConfiguration;
  BootstrapPlatform? checkedPlatform;

  @override
  Future<TrustValidationResult> validate(
    ProvisionedBootstrapConfiguration configuration,
    BootstrapPlatform platform,
  ) async {
    calls += 1;
    checkedConfiguration = configuration;
    checkedPlatform = platform;
    return result;
  }
}

final class FakeHealthReachabilityPort implements HealthReachabilityPort {
  FakeHealthReachabilityPort(HealthReachabilityResult result)
    : _results = Queue.of([result]);

  FakeHealthReachabilityPort.queued(List<HealthReachabilityResult> results)
    : _results = Queue.of(results);

  final Queue<HealthReachabilityResult> _results;
  int calls = 0;
  final checkedOrigins = <Uri>[];

  @override
  Future<HealthReachabilityResult> check(
    ProvisionedBootstrapConfiguration configuration,
  ) async {
    calls += 1;
    checkedOrigins.add(configuration.healthEndpoint);
    if (_results.length > 1) {
      return _results.removeFirst();
    }
    return _results.first;
  }
}

/// Stand-in authority bytes. Nothing in these tests builds a TLS context, so
/// this only needs to be a certificate container, not a usable certificate.
final testCertificateAuthorityPem = Uint8List.fromList(
  utf8.encode('-----BEGIN CERTIFICATE-----\nstub\n-----END CERTIFICATE-----\n'),
);

final testAndroidConfiguration = ProvisionedBootstrapConfiguration(
  serverOrigin: ServerOrigin.parse('https://provisioned.invalid')!,
  trustMaterial: AndroidTrustMaterial(
    privateCaSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    primarySpkiSha256: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
    backupSpkiSha256: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    certificateAuthority: testCertificateAuthorityPem,
  ),
);

final testWebConfiguration = ProvisionedBootstrapConfiguration(
  serverOrigin: ServerOrigin.parse('https://provisioned.invalid')!,
  trustMaterial: const WebTrustMaterial(
    privateCaSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
);
