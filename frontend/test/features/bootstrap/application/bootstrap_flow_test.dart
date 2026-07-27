import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_bootstrap_ports.dart';

void main() {
  group('bootstrap transitions', () {
    test(
      'valid session reaches the online application shell in exact order',
      () async {
        final fixture = _fixture(
          localState: const LocalBootstrapState(
            identity: LocalIdentityState.usable,
            session: LocalSessionState.valid,
          ),
        );

        final states = await _run(fixture.flow);

        expect(states.map((state) => state.runtimeType), [
          LoadingBootstrapConfiguration,
          CheckingProtectedStorage,
          DiscoveringLocalBootstrapState,
          ValidatingBootstrapTrust,
          CheckingBackendHealth,
          BootstrapApplicationReady,
        ]);
        expect((states.last as BootstrapApplicationReady).offline, isFalse);
        expect(fixture.health.checkedOrigins, [
          Uri.parse('https://provisioned.invalid/api/v1/health'),
        ]);
      },
    );

    test(
      'missing configuration blocks before storage or network access',
      () async {
        final configuration = FakeBootstrapConfigurationPort(
          const ConfigurationNotProvisioned(
            ConfigurationFailureKind.missingProvisioning,
          ),
        );
        final fixture = _fixture(configuration: configuration);

        final states = await _run(fixture.flow);

        _expectBlocked(states, BootstrapConnectionIssue.notProvisioned);
        expect(states.map((state) => state.runtimeType), [
          LoadingBootstrapConfiguration,
          BootstrapConnectionBlocked,
        ]);
        expect(fixture.storage.availabilityCalls, 0);
        expect(fixture.trust.calls, 0);
        expect(fixture.health.calls, 0);
      },
    );

    test(
      'unavailable protected storage blocks before discovery and trust',
      () async {
        final fixture = _fixture(
          storage: FakeProtectedStoragePort(
            availability: ProtectedStorageAvailability.unavailable,
          ),
        );

        final states = await _run(fixture.flow);

        _expectBlocked(
          states,
          BootstrapConnectionIssue.protectedStorageUnavailable,
        );
        expect(states.map((state) => state.runtimeType), [
          LoadingBootstrapConfiguration,
          CheckingProtectedStorage,
          BootstrapConnectionBlocked,
        ]);
        expect(fixture.storage.discoveryCalls, 0);
        expect(fixture.trust.calls, 0);
      },
    );

    test('failed local discovery is a protected-storage block', () async {
      final fixture = _fixture(
        storage: FakeProtectedStoragePort(
          discovery: const LocalStateDiscoveryUnavailable(),
        ),
      );

      final states = await _run(fixture.flow);

      _expectBlocked(
        states,
        BootstrapConnectionIssue.protectedStorageUnavailable,
      );
      expect(states.map((state) => state.runtimeType), [
        LoadingBootstrapConfiguration,
        CheckingProtectedStorage,
        DiscoveringLocalBootstrapState,
        BootstrapConnectionBlocked,
      ]);
      expect(fixture.trust.calls, 0);
    });

    for (final failure in TrustFailureKind.values) {
      test(
        'preflight trust failure $failure blocks without a health call',
        () async {
          final fixture = _fixture(
            trust: FakePlatformTrustPort(TrustValidationFailed(failure)),
          );

          final states = await _run(fixture.flow);

          _expectTrustBlocked(states, failure);
          expect(states.map((state) => state.runtimeType), [
            LoadingBootstrapConfiguration,
            CheckingProtectedStorage,
            DiscoveringLocalBootstrapState,
            ValidatingBootstrapTrust,
            BootstrapConnectionBlocked,
          ]);
          expect(fixture.health.calls, 0);
        },
      );
    }

    for (final failure in TrustFailureKind.values) {
      test('TLS health trust failure $failure cannot continue', () async {
        final fixture = _fixture(
          health: FakeHealthReachabilityPort(HealthTrustFailure(failure)),
        );

        final states = await _run(fixture.flow);

        _expectTrustBlocked(states, failure);
        expect(states.map((state) => state.runtimeType), [
          LoadingBootstrapConfiguration,
          CheckingProtectedStorage,
          DiscoveringLocalBootstrapState,
          ValidatingBootstrapTrust,
          CheckingBackendHealth,
          BootstrapConnectionBlocked,
        ]);
      });
    }

    test('reachable fresh installation routes to login', () async {
      final states = await _run(_fixture().flow);

      expect(states.last, isA<BootstrapLoginRequired>());
      expect(
        (states.last as BootstrapLoginRequired).rememberedUsername,
        isNull,
      );
    });

    test(
      'expired session routes to login with only remembered username',
      () async {
        final states = await _run(
          _fixture(
            localState: const LocalBootstrapState(
              identity: LocalIdentityState.usable,
              session: LocalSessionState.expired,
              rememberedUsername: 'remembered-user',
            ),
          ).flow,
        );

        final result = states.last as BootstrapLoginRequired;
        expect(result.rememberedUsername, 'remembered-user');
      },
    );
  });

  group('offline platform policy', () {
    test(
      'Android with a usable identity opens cached content offline',
      () async {
        final states = await _run(
          _fixture(
            health: FakeHealthReachabilityPort(const HealthUnreachable()),
            localState: const LocalBootstrapState(
              identity: LocalIdentityState.usable,
              session: LocalSessionState.expired,
            ),
          ).flow,
        );

        expect(states.last, isA<BootstrapApplicationReady>());
        expect((states.last as BootstrapApplicationReady).offline, isTrue);
      },
    );

    test('Android without a usable identity remains at connection', () async {
      final states = await _run(
        _fixture(
          health: FakeHealthReachabilityPort(const HealthUnreachable()),
        ).flow,
      );

      _expectBlocked(states, BootstrapConnectionIssue.serverUnreachable);
    });

    test('Web with a usable identity remains at connection', () async {
      final states = await _run(
        _fixture(
          platform: BootstrapPlatform.web,
          configurationResult: ConfigurationLoaded(testWebConfiguration),
          health: FakeHealthReachabilityPort(const HealthUnreachable()),
          localState: const LocalBootstrapState(
            identity: LocalIdentityState.usable,
            session: LocalSessionState.valid,
          ),
        ).flow,
      );

      _expectBlocked(states, BootstrapConnectionIssue.serverUnreachable);
    });

    test('an unusable Android identity never enables offline entry', () async {
      final states = await _run(
        _fixture(
          health: FakeHealthReachabilityPort(const HealthUnreachable()),
          localState: const LocalBootstrapState(
            identity: LocalIdentityState.unusable,
            session: LocalSessionState.valid,
          ),
        ).flow,
      );

      _expectBlocked(states, BootstrapConnectionIssue.serverUnreachable);
    });
  });
}

Future<List<BootstrapState>> _run(BootstrapFlow flow) async {
  final states = <BootstrapState>[];
  await flow.run(states.add);
  return states;
}

({
  BootstrapFlow flow,
  FakeProtectedStoragePort storage,
  FakePlatformTrustPort trust,
  FakeHealthReachabilityPort health,
})
_fixture({
  BootstrapPlatform platform = BootstrapPlatform.android,
  ConfigurationLoadResult? configurationResult,
  FakeBootstrapConfigurationPort? configuration,
  FakeProtectedStoragePort? storage,
  FakePlatformTrustPort? trust,
  FakeHealthReachabilityPort? health,
  LocalBootstrapState localState = const LocalBootstrapState.fresh(),
}) {
  final resolvedStorage =
      storage ??
      FakeProtectedStoragePort(discovery: LocalStateDiscovered(localState));
  final resolvedTrust = trust ?? FakePlatformTrustPort();
  final resolvedHealth =
      health ?? FakeHealthReachabilityPort(const HealthReachable());
  final resolvedConfiguration =
      configuration ??
      FakeBootstrapConfigurationPort(
        configurationResult ?? ConfigurationLoaded(testAndroidConfiguration),
      );
  return (
    flow: BootstrapFlow(
      configuration: resolvedConfiguration,
      storage: resolvedStorage,
      trust: resolvedTrust,
      health: resolvedHealth,
      platform: platform,
    ),
    storage: resolvedStorage,
    trust: resolvedTrust,
    health: resolvedHealth,
  );
}

void _expectBlocked(
  List<BootstrapState> states,
  BootstrapConnectionIssue issue,
) {
  expect(states.last, isA<BootstrapConnectionBlocked>());
  expect((states.last as BootstrapConnectionBlocked).issue, issue);
}

void _expectTrustBlocked(
  List<BootstrapState> states,
  TrustFailureKind failure,
) {
  _expectBlocked(states, BootstrapConnectionIssue.trustFailure);
  expect((states.last as BootstrapConnectionBlocked).trustFailure, failure);
}
