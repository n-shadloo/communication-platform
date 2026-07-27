/// The only client platforms supported by this repository.
enum BootstrapPlatform {
  android,
  web;

  bool get canOpenCachedContentOffline => this == BootstrapPlatform.android;
}

/// An HTTPS origin provisioned into the application artifact.
final class ServerOrigin {
  const ServerOrigin._(this.uri);

  final Uri uri;

  static ServerOrigin? parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return ServerOrigin._(uri.replace(path: ''));
  }

  Uri resolve(String absolutePath) => uri.resolve(absolutePath);

  @override
  String toString() => uri.toString();
}

sealed class PlatformTrustMaterial {
  const PlatformTrustMaterial({required this.privateCaSha256});

  /// Public fingerprint distributed through the operator's independent channel.
  final String privateCaSha256;
}

final class AndroidTrustMaterial extends PlatformTrustMaterial {
  const AndroidTrustMaterial({
    required super.privateCaSha256,
    required this.primarySpkiSha256,
    required this.backupSpkiSha256,
  });

  final String primarySpkiSha256;
  final String backupSpkiSha256;
}

/// Browsers cannot install a CA or enforce application-level SPKI pins.
final class WebTrustMaterial extends PlatformTrustMaterial {
  const WebTrustMaterial({required super.privateCaSha256});
}

final class ProvisionedBootstrapConfiguration {
  const ProvisionedBootstrapConfiguration({
    required this.serverOrigin,
    required this.trustMaterial,
  });

  final ServerOrigin serverOrigin;
  final PlatformTrustMaterial trustMaterial;

  /// The sole bootstrap reachability target; no public probe is modeled.
  Uri get healthEndpoint => serverOrigin.resolve('/api/v1/health');
}

enum ConfigurationFailureKind {
  missingProvisioning,
  invalidOrigin,
  invalidPrivateCaFingerprint,
  invalidPrimaryPin,
  invalidBackupPin,
  duplicatePins,
  platformMismatch,
}

sealed class ConfigurationLoadResult {
  const ConfigurationLoadResult();
}

final class ConfigurationLoaded extends ConfigurationLoadResult {
  const ConfigurationLoaded(this.configuration);

  final ProvisionedBootstrapConfiguration configuration;
}

final class ConfigurationNotProvisioned extends ConfigurationLoadResult {
  const ConfigurationNotProvisioned(this.reason);

  final ConfigurationFailureKind reason;
}

enum ProtectedStorageAvailability { available, unavailable }

enum LocalIdentityState { absent, usable, unusable }

enum LocalSessionState { absent, valid, expired }

final class LocalBootstrapState {
  const LocalBootstrapState({
    required this.identity,
    required this.session,
    this.rememberedUsername,
  });

  const LocalBootstrapState.fresh()
    : identity = LocalIdentityState.absent,
      session = LocalSessionState.absent,
      rememberedUsername = null;

  final LocalIdentityState identity;
  final LocalSessionState session;

  /// A username is presentation convenience, not a credential.
  final String? rememberedUsername;

  bool get hasUsableIdentity => identity == LocalIdentityState.usable;
  bool get hasValidSession => session == LocalSessionState.valid;
}

sealed class LocalStateDiscoveryResult {
  const LocalStateDiscoveryResult();
}

final class LocalStateDiscovered extends LocalStateDiscoveryResult {
  const LocalStateDiscovered(this.localState);

  final LocalBootstrapState localState;
}

final class LocalStateDiscoveryUnavailable extends LocalStateDiscoveryResult {
  const LocalStateDiscoveryUnavailable();
}

enum TrustFailureKind {
  invalidProvisioning,
  privateCaRejected,
  spkiPinMismatch,
  browserPrivateCaNotTrusted,
  platformTrustUnavailable,
}

sealed class TrustValidationResult {
  const TrustValidationResult();
}

final class TrustValidated extends TrustValidationResult {
  const TrustValidated();
}

final class TrustValidationFailed extends TrustValidationResult {
  const TrustValidationFailed(this.reason);

  final TrustFailureKind reason;
}

sealed class HealthReachabilityResult {
  const HealthReachabilityResult();
}

final class HealthReachable extends HealthReachabilityResult {
  const HealthReachable();
}

final class HealthUnreachable extends HealthReachabilityResult {
  const HealthUnreachable();
}

final class HealthTrustFailure extends HealthReachabilityResult {
  const HealthTrustFailure(this.reason);

  final TrustFailureKind reason;
}

enum BootstrapConnectionIssue {
  notProvisioned,
  protectedStorageUnavailable,
  trustFailure,
  serverUnreachable,
}

sealed class BootstrapState {
  const BootstrapState();
}

final class LoadingBootstrapConfiguration extends BootstrapState {
  const LoadingBootstrapConfiguration();
}

final class CheckingProtectedStorage extends BootstrapState {
  const CheckingProtectedStorage();
}

final class DiscoveringLocalBootstrapState extends BootstrapState {
  const DiscoveringLocalBootstrapState();
}

final class ValidatingBootstrapTrust extends BootstrapState {
  const ValidatingBootstrapTrust();
}

final class CheckingBackendHealth extends BootstrapState {
  const CheckingBackendHealth();
}

final class BootstrapConnectionBlocked extends BootstrapState {
  const BootstrapConnectionBlocked({
    required this.issue,
    required this.retryAllowed,
    this.trustFailure,
  });

  final BootstrapConnectionIssue issue;
  final bool retryAllowed;
  final TrustFailureKind? trustFailure;
}

final class BootstrapLoginRequired extends BootstrapState {
  const BootstrapLoginRequired({this.rememberedUsername});

  final String? rememberedUsername;
}

final class BootstrapApplicationReady extends BootstrapState {
  const BootstrapApplicationReady({required this.offline});

  final bool offline;
}
