import 'dart:typed_data';

import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/application/contact_services.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'profile author substitution is cached only as unauthenticated ciphertext',
    () async {
      final local = _ProfileLocal();
      final service = ProfileService(
        remote: _ProfileRemote(),
        local: local,
        authentication: _VerifiedAuthentication(),
        protection: _SubstitutedProfileProtection(),
        keyDistribution: _ProfileKeys(),
      );

      final result = await service.refreshPeer('peer');

      expect(result, isA<FailureResult<AuthenticatedProfile?>>());
      expect(local.storedCiphertext, isNotNull);
      expect(local.storedAuthenticated, isNull);
    },
  );

  test(
    'an unverified peer blocks before profile ciphertext is fetched',
    () async {
      final remote = _ProfileRemote();
      final service = ProfileService(
        remote: remote,
        local: _ProfileLocal(),
        authentication: _UnverifiedAuthentication(),
        protection: _SubstitutedProfileProtection(),
        keyDistribution: _ProfileKeys(),
      );

      final result = await service.refreshPeer('peer');

      expect(result, isA<FailureResult<AuthenticatedProfile?>>());
      expect(remote.fetchCalls, 0);
    },
  );
}

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));

final class _ProfileRemote implements ProfileRemotePort {
  var fetchCalls = 0;

  @override
  Future<Result<ProfileCiphertext?>> fetchProfile({
    required String userId,
  }) async {
    fetchCalls += 1;
    return Result.success(ProfileCiphertext(blob: Uint8List(1024), version: 1));
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}

final class _ProfileLocal implements ContactLocalPort {
  ProfileCiphertext? storedCiphertext;
  AuthenticatedProfile? storedAuthenticated;

  @override
  Future<Result<void>> writeProfile(
    String userId,
    ProfileCiphertext ciphertext,
    AuthenticatedProfile? authenticated,
  ) async {
    storedCiphertext = ciphertext;
    storedAuthenticated = authenticated;
    return const Result.success(null);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}

class _VerifiedAuthentication implements PeerAuthenticationService {
  @override
  Future<Result<AuthenticatedPeer>> refreshPeer({
    required String userId,
    required bool requirePrekeys,
  }) async => Result.success(
    AuthenticatedPeer(
      trust: ContactTrustRecord(
        userId: userId,
        state: ContactTrustState.verified,
      ),
      devices: [
        PeerPublicDevice(
          deviceId: 'live-device',
          identityPublic: _bytes(64, 1),
          registrationId: 1,
          crossSignature: _bytes(64, 2),
          bundleVersion: 1,
        ),
      ],
      claimedBundles: const [],
    ),
  );

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}

final class _UnverifiedAuthentication extends _VerifiedAuthentication {
  @override
  Future<Result<AuthenticatedPeer>> refreshPeer({
    required String userId,
    required bool requirePrekeys,
  }) async {
    final verified = await super.refreshPeer(
      userId: userId,
      requirePrekeys: requirePrekeys,
    );
    final peer = (verified as Success<AuthenticatedPeer>).value;
    return Result.success(
      AuthenticatedPeer(
        trust: ContactTrustRecord(
          userId: userId,
          state: ContactTrustState.unverified,
        ),
        devices: peer.devices,
        claimedBundles: const [],
      ),
    );
  }
}

final class _SubstitutedProfileProtection implements ProfileProtectionPort {
  @override
  bool get isProductionReady => false;

  @override
  Future<Result<OpenedProfile>> open({
    required ProfileCiphertext ciphertext,
    required ProfileKeyMaterial key,
  }) async => const Result.success(
    OpenedProfile(
      draft: ProfileDraft(displayName: 'Mallory', avatarSeed: 4),
      authorUserId: 'attacker',
      authorDeviceId: 'live-device',
      revision: 1,
    ),
  );

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}

final class _ProfileKeys implements ProfileKeyDistributionPort {
  @override
  bool get isProductionReady => false;

  @override
  Future<Result<ProfileKeyMaterial?>> receive({
    required String ownerUserId,
    required int profileVersion,
  }) async => Result.success(ProfileKeyMaterial(_bytes(32, 3)));

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}
