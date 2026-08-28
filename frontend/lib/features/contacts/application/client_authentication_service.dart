import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/identity_crypto_port.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';

/// Authentication Service used by profile handling now and by later messaging/MLS.
///
/// Backend listings are treated as untrusted inputs. A successful result chains exact
/// response bytes through master, self-signing, device, prekey, and device-log checks.
final class ClientAuthenticationService
    implements
        PeerAuthenticationService,
        SelectivePeerPrekeyClaimPort,
        VerifiedLiveDeviceResolverPort {
  const ClientAuthenticationService({
    required this.remote,
    required this.local,
    required this.crypto,
    this.resolutionCache = const NoPeerResolutionCache(),
  });

  final PeerIdentityRemotePort remote;
  final ContactLocalPort local;
  final IdentityCryptoPort crypto;

  /// Which of this service's entry points may be served a remembered server
  /// answer, decided here because this is where that is known.
  ///
  /// [refreshPeer] and [confirmOutOfBand] may not. Both exist to answer the
  /// question *is this device's idea of that peer still right* — one is asked
  /// by a person looking at a safety number, the other by the delivery cycle
  /// acting on a `stale_devices` response — and a cache is the one thing that
  /// cannot answer it. They run under [PeerResolutionCachePort.live], which
  /// forgets the peer and keeps it forgotten for the whole resolution.
  ///
  /// [resolveLiveDevices] and [refreshPeerForDevices] may, because they are the
  /// fan-out asking the same question of the same peer two to four times inside
  /// one cycle. Nothing they verify is skipped by a hit; only the round trip is.
  final PeerResolutionCachePort resolutionCache;

  @override
  Future<Result<AuthenticatedPeer>> refreshPeer({
    required String userId,
    required bool requirePrekeys,
  }) => resolutionCache.live(
    userId,
    () => _refresh(
      userId: userId,
      requirePrekeys: requirePrekeys,
      claimDeviceIds: null,
      allowMasterReplacement: false,
    ),
  );

  @override
  Future<Result<AuthenticatedPeer>> refreshPeerForDevices({
    required String userId,
    required List<String> deviceIds,
  }) {
    if (deviceIds.isEmpty ||
        deviceIds.length > 100 ||
        deviceIds.toSet().length != deviceIds.length ||
        deviceIds.any((value) => _uuidBytes(value) == null)) {
      return Future.value(
        const Result.failure(
          SecurityFailure(SecurityFailureKind.policyBlocked),
        ),
      );
    }
    return _refresh(
      userId: userId,
      requirePrekeys: true,
      claimDeviceIds: List.unmodifiable(deviceIds),
      allowMasterReplacement: false,
    );
  }

  @override
  Future<Result<AuthenticatedPeer>> resolveLiveDevices({
    required String userId,
  }) async {
    final globalFork = await local.hasAnyDeviceLogFork();
    if (globalFork case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    if ((globalFork as Success<bool>).value) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    return _refresh(
      userId: userId,
      requirePrekeys: false,
      claimDeviceIds: null,
      allowMasterReplacement: false,
    );
  }

  Future<Result<AuthenticatedPeer>> _refresh({
    required String userId,
    required bool requirePrekeys,
    required List<String>? claimDeviceIds,
    required bool allowMasterReplacement,
  }) async {
    if (requirePrekeys) {
      final globalFork = await local.hasAnyDeviceLogFork();
      if (globalFork case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      if ((globalFork as Success<bool>).value) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.policyBlocked),
        );
      }
    }
    final userBytes = _uuidBytes(userId);
    if (userBytes == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
    final localIdentityResult = await local.readLocalIdentity();
    if (localIdentityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final localIdentity =
        (localIdentityResult as Success<LocalAccountIdentity>).value;
    final previousResult = await local.readTrust(userId);
    if (previousResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final previous = (previousResult as Success<ContactTrustRecord?>).value;
    final identityResult = await remote.fetchIdentity(userId: userId);
    if (identityResult case FailureResult(failure: final failure)) {
      await _persistBlocked(
        previous,
        userId,
        ContactTrustState.identityUnavailable,
      );
      return Result.failure(failure);
    }
    final identity = (identityResult as Success<PeerIdentityPublic>).value;
    final verifiedIdentity = await crypto.verifyIdentity(
      userId: userBytes,
      identity: identity,
    );
    if (verifiedIdentity case FailureResult(failure: final failure)) {
      await _persistBlocked(
        previous,
        userId,
        ContactTrustState.identityUnavailable,
        identity: identity,
      );
      return Result.failure(failure);
    }
    if (localIdentity.userId == userId &&
        (!_same(
              localIdentity.identityPackage.masterPub,
              identity.masterPublic,
            ) ||
            !_same(
              localIdentity.identityPackage.selfSigningPub,
              identity.selfSigningPublic,
            ) ||
            !_same(
              localIdentity.identityPackage.userSigningPub,
              identity.userSigningPublic,
            ) ||
            !_same(
              localIdentity.identityPackage.masterSig,
              identity.masterSignature,
            ))) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final confirmedMaster = previous?.confirmedMasterPublic;
    if (confirmedMaster != null &&
        !_same(confirmedMaster, identity.masterPublic) &&
        !allowMasterReplacement) {
      final changed =
          (previous ??
                  ContactTrustRecord(
                    userId: userId,
                    state: ContactTrustState.masterKeyChanged,
                  ))
              .copyWith(
                state: ContactTrustState.masterKeyChanged,
                identity: identity,
              );
      await local.writeTrust(changed);
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }

    final cachedDevicesResult = await local.readDevices(userId);
    if (cachedDevicesResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final cachedDevices =
        (cachedDevicesResult as Success<List<PeerPublicDevice>>).value;
    final devicesResult = await remote.fetchDevices(
      userId: userId,
      etag: previous?.etag,
    );
    if (devicesResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final refresh = (devicesResult as Success<PeerDeviceRefresh>).value;
    final (devices, etag, advertisedHead, listChanged) = switch (refresh) {
      PeerDevicesNotModified() => (
        cachedDevices,
        previous?.etag,
        previous?.logHeadSequence,
        false,
      ),
      PeerDevicesUpdated(:final devices, :final etag, :final logHeadSequence) =>
        (devices, etag, logHeadSequence, !_sameDevices(cachedDevices, devices)),
    };
    if (devices.isEmpty || devices.any((device) => device.isUnsigned)) {
      await _persistBlocked(
        previous,
        userId,
        ContactTrustState.invalidDevice,
        identity: identity,
        etag: etag,
      );
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    if (advertisedHead == null ||
        (previous?.logHeadSequence != null &&
            advertisedHead < previous!.logHeadSequence!)) {
      return _fork(previous, userId, identity, etag);
    }
    if (!_isValidDeviceTransition(cachedDevices, devices)) {
      return _invalidDevice(previous, userId, identity, etag);
    }
    if (listChanged && advertisedHead == previous?.logHeadSequence) {
      // Device registration, revocation, and prekey rotation are separate
      // server mutations from the signed append. A same-head device-set change
      // is therefore a bounded pending window, not fork evidence. The list is
      // never exposed as authenticated until the extending record arrives.
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }

    var expectedPrevious = previous?.logHeadHash ?? Uint8List(32);
    var after = previous?.logHeadSequence;
    var expectedSequence = (after ?? -1) + 1;
    final verifiedRecords = <VerifiedDeviceLogRecord>[];
    if (after == null || advertisedHead > after) {
      var hasMore = true;
      while (hasMore) {
        final pageResult = await remote.fetchDeviceLog(
          userId: userId,
          after: after,
        );
        if (pageResult case FailureResult(failure: final failure)) {
          return Result.failure(failure);
        }
        final page = (pageResult as Success<PeerDeviceLogPage>).value;
        if (page.headSequence != advertisedHead ||
            (page.records.isEmpty && expectedSequence <= advertisedHead)) {
          return _fork(previous, userId, identity, etag);
        }
        for (final record in page.records) {
          if (record.sequence != expectedSequence) {
            return _fork(previous, userId, identity, etag);
          }
          final inspectedResult = await crypto.inspectPeerDeviceLog(
            userId: userBytes,
            selfSigningPublic: identity.selfSigningPublic,
            liveDevices: devices,
            requireCurrentLiveSet: record.sequence == advertisedHead,
            record: record.blob,
          );
          if (inspectedResult case FailureResult(failure: final failure)) {
            await _persistBlocked(
              previous,
              userId,
              ContactTrustState.deviceLogFork,
              identity: identity,
              etag: etag,
            );
            return Result.failure(failure);
          }
          final inspected =
              (inspectedResult as Success<PeerDeviceLogInspection>).value;
          if (inspected.sequence != record.sequence ||
              !_same(inspected.previousHash, expectedPrevious) ||
              (record.sequence == advertisedHead &&
                  inspected.identityVersion != identity.version)) {
            return _fork(previous, userId, identity, etag);
          }
          verifiedRecords.add(
            VerifiedDeviceLogRecord(
              sequence: record.sequence,
              blob: record.blob,
              hash: inspected.recordHash,
            ),
          );
          expectedPrevious = inspected.recordHash;
          after = record.sequence;
          expectedSequence += 1;
        }
        hasMore = page.hasMore;
      }
      if (after != advertisedHead) {
        return _fork(previous, userId, identity, etag);
      }
    }

    var claimed = const <ClaimedPrekeyBundle>[];
    if (requirePrekeys) {
      final requestedDeviceIds =
          claimDeviceIds ??
          devices.map((device) => device.deviceId).toList(growable: false);
      final liveDeviceIds = devices.map((device) => device.deviceId).toSet();
      if (requestedDeviceIds.any(
        (deviceId) => !liveDeviceIds.contains(deviceId),
      )) {
        return _invalidDevice(previous, userId, identity, etag);
      }
      final claimResult = await remote.claimPrekeyBundles(
        userId: userId,
        deviceIds: requestedDeviceIds,
      );
      if (claimResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      claimed = (claimResult as Success<List<ClaimedPrekeyBundle>>).value;
      if (claimed.length != requestedDeviceIds.length) {
        return _invalidDevice(previous, userId, identity, etag);
      }
      for (final deviceId in requestedDeviceIds) {
        final device = devices.singleWhere(
          (candidate) => candidate.deviceId == deviceId,
        );
        final matches = claimed
            .where((bundle) => bundle.deviceId == device.deviceId)
            .toList(growable: false);
        if (matches.length != 1 ||
            !matches.single.hasPostQuantumSignedPrekey ||
            !_bundleMatches(device, matches.single)) {
          return _invalidDevice(previous, userId, identity, etag);
        }
        final verified = await crypto.verifyClaimedBundle(
          userId: userBytes,
          deviceId: _uuidBytes(device.deviceId)!,
          selfSigningPublic: identity.selfSigningPublic,
          bundle: matches.single,
        );
        if (verified case FailureResult()) {
          return _invalidDevice(previous, userId, identity, etag);
        }
      }
    }

    var nextState = ContactTrustState.unverified;
    if (confirmedMaster != null &&
        _same(confirmedMaster, identity.masterPublic) &&
        previous?.attestation != null) {
      final attestation = await crypto.verifyUserAttestation(
        signerUserId: _uuidBytes(localIdentity.userId)!,
        signerUserSigningPublic: localIdentity.identityPackage.userSigningPub,
        peerUserId: userBytes,
        peerMasterPublic: identity.masterPublic,
        attestation: previous!.attestation!,
      );
      if (attestation case Success()) {
        nextState = ContactTrustState.verified;
      }
    }
    final trust = ContactTrustRecord(
      userId: userId,
      state: nextState,
      identity: identity,
      confirmedMasterPublic: confirmedMaster,
      attestation: previous?.attestation,
      etag: etag,
      logHeadSequence: advertisedHead,
      logHeadHash: verifiedRecords.isEmpty
          ? previous?.logHeadHash
          : verifiedRecords.last.hash,
    );
    final storedDevices = await local.replaceDevices(userId, devices);
    if (storedDevices case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final storedRecords = await local.appendVerifiedLogRecords(
      userId,
      verifiedRecords,
    );
    if (storedRecords case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final storedTrust = await local.writeTrust(trust);
    if (storedTrust case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return Result.success(
      AuthenticatedPeer(
        trust: trust,
        devices: devices,
        claimedBundles: claimed,
      ),
    );
  }

  @override
  Future<Result<ContactTrustRecord>> confirmOutOfBand({
    required String userId,
    required Uint8List exactMasterPublic,
  }) => resolutionCache.live(
    userId,
    () =>
        _confirmOutOfBand(userId: userId, exactMasterPublic: exactMasterPublic),
  );

  Future<Result<ContactTrustRecord>> _confirmOutOfBand({
    required String userId,
    required Uint8List exactMasterPublic,
  }) async {
    final refreshed = await _refresh(
      userId: userId,
      requirePrekeys: false,
      claimDeviceIds: null,
      allowMasterReplacement: true,
    );
    if (refreshed case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final peer = (refreshed as Success<AuthenticatedPeer>).value;
    final identity = peer.trust.identity;
    if (identity == null || !_same(identity.masterPublic, exactMasterPublic)) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    final localIdentityResult = await local.readLocalIdentity();
    if (localIdentityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final localIdentity =
        (localIdentityResult as Success<LocalAccountIdentity>).value;
    final attested = await crypto.attestPeerMaster(
      localIdentity: localIdentity.identityPackage,
      peerUserId: _uuidBytes(userId)!,
      peerMasterPublic: identity.masterPublic,
    );
    if (attested case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final trust = ContactTrustRecord(
      userId: userId,
      state: ContactTrustState.verified,
      identity: identity,
      confirmedMasterPublic: identity.masterPublic,
      attestation: (attested as Success<UserSigningAttestation>).value,
      etag: peer.trust.etag,
      logHeadSequence: peer.trust.logHeadSequence,
      logHeadHash: peer.trust.logHeadHash,
    );
    final written = await local.writeTrust(trust);
    return written.fold(
      onSuccess: (_) => Result.success(trust),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint(String userId) async {
    final peerResult = await local.readTrust(userId);
    final localResult = await local.readLocalIdentity();
    if (peerResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    if (localResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final peer = (peerResult as Success<ContactTrustRecord?>).value;
    final identity = peer?.identity;
    if (identity == null) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    final localIdentity = (localResult as Success<LocalAccountIdentity>).value;
    return crypto.safetyFingerprint(
      localUserId: _uuidBytes(localIdentity.userId)!,
      localMasterPublic: localIdentity.identityPackage.masterPub,
      peerUserId: _uuidBytes(userId)!,
      peerMasterPublic: identity.masterPublic,
    );
  }

  Future<Result<AuthenticatedPeer>> _fork(
    ContactTrustRecord? previous,
    String userId,
    PeerIdentityPublic identity,
    String? etag,
  ) async {
    await _persistBlocked(
      previous,
      userId,
      ContactTrustState.deviceLogFork,
      identity: identity,
      etag: etag,
    );
    return const Result.failure(
      SecurityFailure(SecurityFailureKind.policyBlocked),
    );
  }

  Future<Result<AuthenticatedPeer>> _invalidDevice(
    ContactTrustRecord? previous,
    String userId,
    PeerIdentityPublic identity,
    String? etag,
  ) async {
    await _persistBlocked(
      previous,
      userId,
      ContactTrustState.invalidDevice,
      identity: identity,
      etag: etag,
    );
    return const Result.failure(
      SecurityFailure(SecurityFailureKind.unauthenticatedInput),
    );
  }

  Future<void> _persistBlocked(
    ContactTrustRecord? previous,
    String userId,
    ContactTrustState state, {
    PeerIdentityPublic? identity,
    String? etag,
  }) async {
    await local.writeTrust(
      ContactTrustRecord(
        userId: userId,
        state: state,
        identity: identity ?? previous?.identity,
        confirmedMasterPublic: previous?.confirmedMasterPublic,
        attestation: previous?.attestation,
        etag: etag ?? previous?.etag,
        logHeadSequence: previous?.logHeadSequence,
        logHeadHash: previous?.logHeadHash,
      ),
    );
  }

  bool _bundleMatches(PeerPublicDevice device, ClaimedPrekeyBundle bundle) =>
      device.deviceId == bundle.deviceId &&
      device.registrationId == bundle.registrationId &&
      device.bundleVersion == bundle.bundleVersion &&
      _same(device.identityPublic, bundle.identityPublic) &&
      _same(device.crossSignature!, bundle.crossSignature);

  bool _sameDevices(List<PeerPublicDevice> left, List<PeerPublicDevice> right) {
    if (left.length != right.length) {
      return false;
    }
    final a = [...left]..sort((x, y) => x.deviceId.compareTo(y.deviceId));
    final b = [...right]..sort((x, y) => x.deviceId.compareTo(y.deviceId));
    for (var index = 0; index < a.length; index += 1) {
      if (a[index].deviceId != b[index].deviceId ||
          a[index].registrationId != b[index].registrationId ||
          a[index].bundleVersion != b[index].bundleVersion ||
          !_same(a[index].identityPublic, b[index].identityPublic) ||
          !_nullableSame(a[index].crossSignature, b[index].crossSignature)) {
        return false;
      }
    }
    return true;
  }

  bool _isValidDeviceTransition(
    List<PeerPublicDevice> previous,
    List<PeerPublicDevice> current,
  ) {
    final oldById = {for (final device in previous) device.deviceId: device};
    for (final device in current) {
      final old = oldById[device.deviceId];
      if (old == null) {
        continue;
      }
      if (old.registrationId != device.registrationId ||
          !_same(old.identityPublic, device.identityPublic)) {
        return false;
      }
      final signatureChanged = !_nullableSame(
        old.crossSignature,
        device.crossSignature,
      );
      final versionChanged = old.bundleVersion != device.bundleVersion;
      if (signatureChanged != versionChanged) {
        return false;
      }
      if (signatureChanged &&
          (old.bundleVersion == null ||
              device.bundleVersion != old.bundleVersion! + 1)) {
        return false;
      }
    }
    return true;
  }

  bool _nullableSame(Uint8List? left, Uint8List? right) =>
      left == null || right == null
      ? left == null && right == null
      : _same(left, right);

  bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  Uint8List? _uuidBytes(String value) {
    final compact = value.replaceAll('-', '');
    if (compact.length != 32 ||
        !RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(compact)) {
      return null;
    }
    return Uint8List.fromList([
      for (var index = 0; index < compact.length; index += 2)
        int.parse(compact.substring(index, index + 2), radix: 16),
    ]);
  }
}
