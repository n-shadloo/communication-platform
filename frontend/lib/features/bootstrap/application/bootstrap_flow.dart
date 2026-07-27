import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';

typedef BootstrapStateListener = void Function(BootstrapState state);

/// Explicit, single-run bootstrap state machine.
final class BootstrapFlow {
  const BootstrapFlow({
    required this.configuration,
    required this.storage,
    required this.trust,
    required this.health,
    required this.platform,
  });

  final BootstrapConfigurationPort configuration;
  final ProtectedStorageBootstrapPort storage;
  final PlatformTrustPort trust;
  final HealthReachabilityPort health;
  final BootstrapPlatform platform;

  Future<BootstrapState> run(BootstrapStateListener onState) async {
    final machine = _BootstrapStateMachine(onState);
    machine.emit(const LoadingBootstrapConfiguration());

    final configurationResult = await configuration.load();
    if (configurationResult is ConfigurationNotProvisioned) {
      return machine.emit(
        const BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.notProvisioned,
          retryAllowed: false,
        ),
      );
    }
    final provisionedConfiguration =
        (configurationResult as ConfigurationLoaded).configuration;

    machine.emit(const CheckingProtectedStorage());
    final storageAvailability = await storage.checkAvailability();
    if (storageAvailability == ProtectedStorageAvailability.unavailable) {
      return machine.emit(
        const BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.protectedStorageUnavailable,
          retryAllowed: true,
        ),
      );
    }

    machine.emit(const DiscoveringLocalBootstrapState());
    final discovery = await storage.discoverLocalState();
    if (discovery is LocalStateDiscoveryUnavailable) {
      return machine.emit(
        const BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.protectedStorageUnavailable,
          retryAllowed: true,
        ),
      );
    }
    final localState = (discovery as LocalStateDiscovered).localState;

    machine.emit(const ValidatingBootstrapTrust());
    final trustResult = await trust.validate(
      provisionedConfiguration,
      platform,
    );
    if (trustResult is TrustValidationFailed) {
      return machine.emit(
        BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.trustFailure,
          retryAllowed: true,
          trustFailure: trustResult.reason,
        ),
      );
    }

    machine.emit(const CheckingBackendHealth());
    final healthResult = await health.check(provisionedConfiguration);
    if (healthResult is HealthTrustFailure) {
      return machine.emit(
        BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.trustFailure,
          retryAllowed: true,
          trustFailure: healthResult.reason,
        ),
      );
    }
    if (healthResult is HealthUnreachable) {
      if (platform.canOpenCachedContentOffline &&
          localState.hasUsableIdentity) {
        return machine.emit(const BootstrapApplicationReady(offline: true));
      }
      return machine.emit(
        const BootstrapConnectionBlocked(
          issue: BootstrapConnectionIssue.serverUnreachable,
          retryAllowed: true,
        ),
      );
    }

    if (localState.hasValidSession) {
      return machine.emit(const BootstrapApplicationReady(offline: false));
    }
    return machine.emit(
      BootstrapLoginRequired(rememberedUsername: localState.rememberedUsername),
    );
  }
}

final class _BootstrapStateMachine {
  _BootstrapStateMachine(this._listener);

  final BootstrapStateListener _listener;
  BootstrapState? _current;

  T emit<T extends BootstrapState>(T next) {
    final current = _current;
    if (!_isAllowed(current, next)) {
      throw StateError(
        'Invalid bootstrap transition: ${current.runtimeType} -> ${next.runtimeType}',
      );
    }
    _current = next;
    _listener(next);
    return next;
  }

  bool _isAllowed(BootstrapState? current, BootstrapState next) {
    if (current == null) {
      return next is LoadingBootstrapConfiguration;
    }
    return switch (current) {
      LoadingBootstrapConfiguration() =>
        next is CheckingProtectedStorage || next is BootstrapConnectionBlocked,
      CheckingProtectedStorage() =>
        next is DiscoveringLocalBootstrapState ||
            next is BootstrapConnectionBlocked,
      DiscoveringLocalBootstrapState() =>
        next is ValidatingBootstrapTrust || next is BootstrapConnectionBlocked,
      ValidatingBootstrapTrust() =>
        next is CheckingBackendHealth || next is BootstrapConnectionBlocked,
      CheckingBackendHealth() =>
        next is BootstrapConnectionBlocked ||
            next is BootstrapLoginRequired ||
            next is BootstrapApplicationReady,
      BootstrapConnectionBlocked() ||
      BootstrapLoginRequired() ||
      BootstrapApplicationReady() => false,
    };
  }
}
