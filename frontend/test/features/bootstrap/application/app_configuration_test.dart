import 'dart:convert';

import 'package:communication_platform/app/config/app_configuration.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _ca = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _primaryPin = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
const _backupPin = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';

/// Base64 of a PEM certificate container. Configuration only checks the shape;
/// whether the certificate is usable as a TLS anchor is the platform's call.
final _caPem = base64.encode(
  utf8.encode('-----BEGIN CERTIFICATE-----\nstub\n-----END CERTIFICATE-----\n'),
);

void main() {
  test(
    'production loads exactly its single provisioned HTTPS origin',
    () async {
      final loader = CompileTimeBootstrapConfiguration(
        environment: AppEnvironment.production,
        platform: BootstrapPlatform.android,
        provisioningValues: AppProvisioningValues(
          serverOrigin: 'https://provisioned.invalid',
          privateCaSha256: _ca,
          primarySpkiSha256: _primaryPin,
          backupSpkiSha256: _backupPin,
          privateCaPemBase64: _caPem,
        ),
      );

      final result = await loader.load() as ConfigurationLoaded;

      expect(
        result.configuration.serverOrigin.toString(),
        'https://provisioned.invalid',
      );
      expect(
        result.configuration.healthEndpoint.toString(),
        'https://provisioned.invalid/api/v1/health',
      );
      expect(result.configuration.trustMaterial, isA<AndroidTrustMaterial>());
    },
  );

  test('production runtime policy exposes no weakening capability', () {
    const policy = AppRuntimePolicy.lockedDown;

    expect(policy.allowsArbitraryServerSelection, isFalse);
    expect(policy.allowsCertificateBypass, isFalse);
    expect(policy.allowsPublicConnectivityProbes, isFalse);
    expect(policy.allowsRemoteConfiguration, isFalse);
    expect(policy.allowsTelemetry, isFalse);
    expect(policy.allowsThirdPartyRuntimeResources, isFalse);
  });

  test('Web keeps CA fingerprint but never models native SPKI pins', () async {
    const loader = CompileTimeBootstrapConfiguration(
      environment: AppEnvironment.production,
      platform: BootstrapPlatform.web,
      provisioningValues: AppProvisioningValues(
        serverOrigin: 'https://provisioned.invalid',
        privateCaSha256: _ca,
        primarySpkiSha256: '',
        backupSpkiSha256: '',
      ),
    );

    final result = await loader.load() as ConfigurationLoaded;

    expect(result.configuration.trustMaterial, isA<WebTrustMaterial>());
    expect(
      result.configuration.trustMaterial,
      isNot(isA<AndroidTrustMaterial>()),
    );
  });

  for (final testCase
      in <
        ({
          String name,
          AppProvisioningValues values,
          ConfigurationFailureKind expected,
        })
      >[
        (
          name: 'missing values',
          values: const AppProvisioningValues(
            serverOrigin: '',
            privateCaSha256: '',
            primarySpkiSha256: '',
            backupSpkiSha256: '',
          ),
          expected: ConfigurationFailureKind.missingProvisioning,
        ),
        (
          name: 'non-HTTPS origin',
          values: const AppProvisioningValues(
            serverOrigin: 'http://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
          ),
          expected: ConfigurationFailureKind.invalidOrigin,
        ),
        (
          name: 'origin with a path',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid/alternate',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
          ),
          expected: ConfigurationFailureKind.invalidOrigin,
        ),
        (
          name: 'bad CA fingerprint',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: 'not-a-fingerprint',
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
          ),
          expected: ConfigurationFailureKind.invalidPrivateCaFingerprint,
        ),
        (
          name: 'bad primary pin',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: 'bad',
            backupSpkiSha256: _backupPin,
          ),
          expected: ConfigurationFailureKind.invalidPrimaryPin,
        ),
        (
          name: 'bad backup pin',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: 'bad',
          ),
          expected: ConfigurationFailureKind.invalidBackupPin,
        ),
        (
          name: 'duplicate pins',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _primaryPin,
          ),
          expected: ConfigurationFailureKind.duplicatePins,
        ),
        // Without the authority the transport has nothing to verify against.
        // Blocking here is what stops the client from silently falling back to
        // the public root store and trusting whatever a network can present.
        (
          name: 'absent private CA certificate',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
          ),
          expected: ConfigurationFailureKind.invalidPrivateCaCertificate,
        ),
        (
          name: 'private CA that is not base64',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
            privateCaPemBase64: 'not base64 at all',
          ),
          expected: ConfigurationFailureKind.invalidPrivateCaCertificate,
        ),
        (
          name: 'private CA that is not a certificate',
          values: const AppProvisioningValues(
            serverOrigin: 'https://provisioned.invalid',
            privateCaSha256: _ca,
            primarySpkiSha256: _primaryPin,
            backupSpkiSha256: _backupPin,
            // Valid base64, but a private key rather than a certificate.
            privateCaPemBase64: 'LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCg==',
          ),
          expected: ConfigurationFailureKind.invalidPrivateCaCertificate,
        ),
      ]) {
    test('invalid production provisioning blocks: ${testCase.name}', () async {
      final result = await CompileTimeBootstrapConfiguration(
        environment: AppEnvironment.production,
        platform: BootstrapPlatform.android,
        provisioningValues: testCase.values,
      ).load();

      expect(result, isA<ConfigurationNotProvisioned>());
      expect((result as ConfigurationNotProvisioned).reason, testCase.expected);
    });
  }
}
