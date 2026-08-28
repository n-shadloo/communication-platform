import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';
import 'package:communication_platform/features/pairwise/application/ports/pairwise_orchestration_ports.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/verified_bundle_request.dart';

/// Reuses the account/device-log verified selective-claim path so MLS and the
/// Double Ratchet authenticate the exact same device bundle.
final class PairwiseGroupKeyPackageAuthentication
    implements GroupKeyPackageAuthenticationPort {
  const PairwiseGroupKeyPackageAuthentication(this.claims);

  final PairwiseSelectiveClaimPort claims;

  @override
  Future<Result<GroupKeyPackageAuthenticationEvidence>>
  authenticateCurrentDevice({
    required String userId,
    required String deviceId,
  }) async {
    final normalizedUser = userId.toLowerCase();
    final normalizedDevice = deviceId.toLowerCase();
    final result = await claims.claimVerifiedDevices(
      userId: normalizedUser,
      deviceIds: [normalizedDevice],
    );
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final verified = (result as Success<VerifiedPairwiseClaims>).value;
    final claim = verified.claims[normalizedDevice];
    final live = verified.liveDevices
        .where(
          (device) =>
              device.userId == normalizedUser &&
              device.deviceId == normalizedDevice,
        )
        .toList(growable: false);
    if (claim == null ||
        claim.device.userId != normalizedUser ||
        claim.device.deviceId != normalizedDevice ||
        live.length != 1 ||
        verified.claims.length != 1) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    try {
      return Result.success(
        GroupKeyPackageAuthenticationEvidence(
          localVerifiedBundleRequest: encodeVerifiedClaimedBundleRequest(
            userId: uuidProtocolBytes(normalizedUser),
            deviceId: uuidProtocolBytes(normalizedDevice),
            selfSigningPublic: claim.device.selfSigningPublic,
            bundle: claim.bundle,
          ),
        ),
      );
    } on VerifiedBundleRequestFormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
  }

  @override
  Future<Result<GroupPeerAuthenticationEvidence>> authenticatePeerDevices({
    required String userId,
    required List<String> deviceIds,
  }) async {
    final normalizedUser = userId.toLowerCase();
    final requested = deviceIds
        .map((value) => value.toLowerCase())
        .toList(growable: false);
    if (requested.isEmpty || requested.toSet().length != requested.length) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final result = await claims.claimVerifiedDevices(
      userId: normalizedUser,
      deviceIds: requested,
    );
    if (result case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final verified = (result as Success<VerifiedPairwiseClaims>).value;
    final live = verified.liveDevices
        .where((device) => device.userId == normalizedUser)
        .toList(growable: false);
    final liveIds = live.map((device) => device.deviceId).toSet();
    if (live.length != verified.liveDevices.length ||
        liveIds.length != live.length ||
        verified.claims.length != requested.length ||
        !verified.claims.keys.toSet().containsAll(requested) ||
        !requested.toSet().containsAll(verified.claims.keys)) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
    try {
      final authenticated = <GroupAuthenticatedPeerDevice>[];
      for (final deviceId in requested) {
        final claim = verified.claims[deviceId];
        if (claim == null ||
            claim.device.userId != normalizedUser ||
            claim.device.deviceId != deviceId ||
            !liveIds.contains(deviceId)) {
          throw const VerifiedBundleRequestFormatException();
        }
        authenticated.add(
          GroupAuthenticatedPeerDevice(
            userId: normalizedUser,
            deviceId: deviceId,
            verifiedBundleRequest: encodeVerifiedClaimedBundleRequest(
              userId: uuidProtocolBytes(normalizedUser),
              deviceId: uuidProtocolBytes(deviceId),
              selfSigningPublic: claim.device.selfSigningPublic,
              bundle: claim.bundle,
            ),
          ),
        );
      }
      return Result.success(
        GroupPeerAuthenticationEvidence(
          userId: normalizedUser,
          liveDeviceIds: live.map((device) => device.deviceId),
          authenticatedDevices: authenticated,
        ),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.unauthenticatedInput),
      );
    }
  }
}
