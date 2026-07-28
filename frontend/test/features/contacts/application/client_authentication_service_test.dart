import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/identity_crypto_port.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/application/client_authentication_service.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientAuthenticationService', () {
    test(
      'rejects malicious master-signature substitution and persists block',
      () async {
        final harness = _Harness()..crypto.rejectIdentity = true;

        final result = await harness.service.refreshPeer(
          userId: _peerUserId,
          requirePrekeys: true,
        );

        expect(result, isA<FailureResult<AuthenticatedPeer>>());
        expect(
          harness.local.trust?.state,
          ContactTrustState.identityUnavailable,
        );
        expect(harness.remote.claimCalls, 0);
      },
    );

    test('rejects an unsigned device before claiming prekeys', () async {
      final harness = _Harness();
      harness.remote.devices = [
        PeerPublicDevice(
          deviceId: _peerDeviceId,
          identityPublic: _bytes(64, 7),
          registrationId: 9,
          bundleVersion: null,
        ),
      ];

      final result = await harness.service.refreshPeer(
        userId: _peerUserId,
        requirePrekeys: true,
      );

      expect(result, isA<FailureResult<AuthenticatedPeer>>());
      expect(harness.local.trust?.state, ContactTrustState.invalidDevice);
      expect(harness.remote.claimCalls, 0);
    });

    test('uses ETag cache and does not replay an unchanged log', () async {
      final harness = _Harness();

      final first = await harness.service.refreshPeer(
        userId: _peerUserId,
        requirePrekeys: true,
      );
      harness.remote.notModified = true;
      final second = await harness.service.refreshPeer(
        userId: _peerUserId,
        requirePrekeys: true,
      );

      expect(first, isA<Success<AuthenticatedPeer>>());
      expect(second, isA<Success<AuthenticatedPeer>>());
      expect(harness.remote.etags, [null, '"devices-v1"']);
      expect(harness.remote.logCalls, 1);
      expect(harness.local.records, hasLength(1));
    });

    test(
      'master-key change blocks and cannot reach sensitive key claims',
      () async {
        final harness = _Harness();
        harness.local.trust = ContactTrustRecord(
          userId: _peerUserId,
          state: ContactTrustState.verified,
          identity: harness.remote.identity,
          confirmedMasterPublic: harness.remote.identity.masterPublic,
          attestation: UserSigningAttestation(_bytes(64, 5)),
        );
        harness.remote.identity = _identity(master: 99);

        final result = await harness.service.refreshPeer(
          userId: _peerUserId,
          requirePrekeys: true,
        );

        expect(result, isA<FailureResult<AuthenticatedPeer>>());
        expect(harness.local.trust?.state, ContactTrustState.masterKeyChanged);
        expect(harness.remote.deviceCalls, 0);
        expect(harness.remote.claimCalls, 0);
      },
    );

    test(
      'device-list change without a new transparency head is a fork',
      () async {
        final harness = _Harness();
        harness.local
          ..devices = [_device()]
          ..trust = ContactTrustRecord(
            userId: _peerUserId,
            state: ContactTrustState.verified,
            identity: harness.remote.identity,
            confirmedMasterPublic: harness.remote.identity.masterPublic,
            attestation: UserSigningAttestation(_bytes(64, 5)),
            etag: '"old"',
            logHeadSequence: 0,
            logHeadHash: _bytes(32, 11),
          );
        harness.remote.devices = [
          PeerPublicDevice(
            deviceId: _peerDeviceId,
            identityPublic: _bytes(64, 8),
            registrationId: 9,
            crossSignature: _bytes(64, 4),
            bundleVersion: 1,
          ),
        ];

        final result = await harness.service.refreshPeer(
          userId: _peerUserId,
          requirePrekeys: true,
        );

        expect(result, isA<FailureResult<AuthenticatedPeer>>());
        expect(harness.local.trust?.state, ContactTrustState.deviceLogFork);
        expect(harness.remote.claimCalls, 0);
      },
    );

    test(
      'any persisted device-log fork blocks all sensitive refreshes',
      () async {
        final harness = _Harness()..local.anyFork = true;

        final result = await harness.service.refreshPeer(
          userId: _peerUserId,
          requirePrekeys: true,
        );

        expect(result, isA<FailureResult<AuthenticatedPeer>>());
        expect(harness.remote.identityCalls, 0);
      },
    );
  });
}

const _peerUserId = '11111111-1111-4111-8111-111111111111';
const _peerDeviceId = '22222222-2222-4222-8222-222222222222';
const _localUserId = '33333333-3333-4333-8333-333333333333';
const _localDeviceId = '44444444-4444-4444-8444-444444444444';

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));

PeerIdentityPublic _identity({int master = 1}) => PeerIdentityPublic(
  masterPublic: _bytes(32, master),
  selfSigningPublic: _bytes(32, 2),
  userSigningPublic: _bytes(32, 3),
  masterSignature: _bytes(64, 4),
  version: 1,
);

PeerPublicDevice _device() => PeerPublicDevice(
  deviceId: _peerDeviceId,
  identityPublic: _bytes(64, 7),
  registrationId: 9,
  crossSignature: _bytes(64, 4),
  bundleVersion: 1,
);

ClaimedPrekeyBundle _bundle() => ClaimedPrekeyBundle(
  deviceId: _peerDeviceId,
  registrationId: 9,
  identityPublic: _bytes(64, 7),
  signedPrekeyId: 1,
  signedPrekeyPublic: _bytes(32, 8),
  signedPrekeySignature: _bytes(64, 9),
  crossSignature: _bytes(64, 4),
  bundleVersion: 1,
  pqSignedPrekeyId: 2,
  pqSignedPrekeyPublic: _bytes(1184, 10),
  pqSignedPrekeySignature: _bytes(64, 11),
);

final class _Harness {
  _Harness() {
    remote = _Remote();
    local = _Local();
    crypto = _Crypto();
    service = ClientAuthenticationService(
      remote: remote,
      local: local,
      crypto: crypto,
    );
  }

  late final _Remote remote;
  late final _Local local;
  late final _Crypto crypto;
  late final ClientAuthenticationService service;
}

final class _Remote implements PeerIdentityRemotePort {
  PeerIdentityPublic identity = _identity();
  List<PeerPublicDevice> devices = [_device()];
  var notModified = false;
  var identityCalls = 0;
  var deviceCalls = 0;
  var claimCalls = 0;
  var logCalls = 0;
  final etags = <String?>[];

  @override
  Future<Result<PeerIdentityPublic>> fetchIdentity({
    required String userId,
  }) async {
    identityCalls += 1;
    return Result.success(identity);
  }

  @override
  Future<Result<PeerDeviceRefresh>> fetchDevices({
    required String userId,
    String? etag,
  }) async {
    deviceCalls += 1;
    etags.add(etag);
    if (notModified) return const Result.success(PeerDevicesNotModified());
    return Result.success(
      PeerDevicesUpdated(
        devices: devices,
        etag: '"devices-v1"',
        logHeadSequence: 0,
      ),
    );
  }

  @override
  Future<Result<List<ClaimedPrekeyBundle>>> claimPrekeyBundles({
    required String userId,
    required List<String> deviceIds,
  }) async {
    claimCalls += 1;
    return Result.success([_bundle()]);
  }

  @override
  Future<Result<PeerDeviceLogPage>> fetchDeviceLog({
    required String userId,
    int? after,
  }) async {
    logCalls += 1;
    return Result.success(
      PeerDeviceLogPage(
        records: [PeerDeviceLogRecord(sequence: 0, blob: _bytes(8, 12))],
        hasMore: false,
        headSequence: 0,
      ),
    );
  }
}

final class _Local implements ContactLocalPort {
  ContactTrustRecord? trust;
  List<PeerPublicDevice> devices = [];
  final records = <VerifiedDeviceLogRecord>[];
  var anyFork = false;

  @override
  Future<Result<bool>> hasAnyDeviceLogFork() async => Result.success(anyFork);

  @override
  Future<Result<ContactTrustRecord?>> readTrust(String userId) async =>
      Result.success(trust);

  @override
  Future<Result<void>> writeTrust(ContactTrustRecord trust) async {
    this.trust = trust;
    return const Result.success(null);
  }

  @override
  Future<Result<List<PeerPublicDevice>>> readDevices(String userId) async =>
      Result.success(devices);

  @override
  Future<Result<void>> replaceDevices(
    String userId,
    List<PeerPublicDevice> devices,
  ) async {
    this.devices = devices;
    return const Result.success(null);
  }

  @override
  Future<Result<void>> appendVerifiedLogRecords(
    String userId,
    List<VerifiedDeviceLogRecord> records,
  ) async {
    this.records.addAll(records);
    return const Result.success(null);
  }

  @override
  Future<Result<LocalAccountIdentity>> readLocalIdentity() async =>
      Result.success(
        LocalAccountIdentity(
          userId: _localUserId,
          deviceId: _localDeviceId,
          username: 'local',
          identityPackage: IdentityKeyPackage.fromNative(_identityPackage()),
        ),
      );

  @override
  Future<Result<void>> replaceDirectory(List<DirectoryUser> users) async =>
      const Result.success(null);

  @override
  Stream<ContactProjection?> watchContact(String userId) =>
      const Stream.empty();

  @override
  Stream<List<ContactProjection>> watchContacts({required String ownUserId}) =>
      const Stream.empty();

  @override
  Future<Result<void>> writeProfile(
    String userId,
    ProfileCiphertext ciphertext,
    AuthenticatedProfile? authenticated,
  ) async => const Result.success(null);
}

final class _Crypto implements IdentityCryptoPort {
  var rejectIdentity = false;

  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) async => rejectIdentity
      ? const Result.failure(
          SecurityFailure(SecurityFailureKind.unauthenticatedInput),
        )
      : const Result.success(null);

  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) async => const Result.success(null);

  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) async => Result.success(
    PeerDeviceLogInspection(
      sequence: 0,
      previousHash: Uint8List(32),
      recordHash: _bytes(32, 11),
      liveDeviceSetHash: _bytes(32, 12),
      identityVersion: 1,
    ),
  );

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) async => Result.success(UserSigningAttestation(_bytes(64, 5)));

  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) async => const Result.success(null);

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) async => Result.success(SafetyFingerprint(_bytes(32, 42)));
}

Uint8List _identityPackage() {
  final recovery = Uint8List(0);
  final backup = Uint8List(0);
  final bytes = BytesBuilder(copy: false)
    ..add('CPIDV001'.codeUnits)
    ..addByte(0)
    ..add(_bytes(16, 3))
    ..add(_bytes(32, 1))
    ..add(_bytes(32, 2))
    ..add(_bytes(32, 3))
    ..add(_bytes(64, 4))
    ..add([0, recovery.length])
    ..add([0, 0, 0, backup.length])
    ..add(_bytes(96, 5))
    ..add(recovery)
    ..add(backup);
  return bytes.toBytes();
}
