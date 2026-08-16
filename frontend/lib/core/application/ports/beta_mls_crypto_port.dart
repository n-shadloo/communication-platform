import 'dart:typed_data';

import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/result.dart';

/// Low-level opaque bridge to the closed-beta Rust MLS core.
abstract interface class BetaMlsCryptoPort {
  Future<Result<GeneratedMlsKeyPackages>> generateBetaMlsKeyPackages(
    MlsKeyPackageGenerationRequest request,
  );

  Future<Result<BetaMlsCommitOutput>> createBetaMlsGroup(
    BetaMlsCreateRequest request,
  );

  Future<Result<BetaMlsJoinOutput>> joinBetaMlsGroup(
    BetaMlsJoinRequest request,
  );

  Future<Result<BetaMlsCommitOutput>> addBetaMlsMembers(
    BetaMlsAddMembersRequest request,
  );

  Future<Result<BetaMlsCommitOutput>> removeBetaMlsMembers(
    BetaMlsRemoveMembersRequest request,
  );

  Future<Result<BetaMlsMessageOutput>> sendBetaMlsApplication(
    BetaMlsSendApplicationRequest request,
  );

  Future<Result<BetaMlsProcessedMessage>> processBetaMlsMessage(
    BetaMlsProcessMessageRequest request,
  );

  Future<Result<BetaMlsMessageOutput>> proposeBetaMlsUpdate(
    BetaMlsPendingCommitRequest request,
  );

  Future<Result<BetaMlsCommitOutput>> commitBetaMlsPendingProposals(
    BetaMlsPendingCommitRequest request,
  );

  Future<Result<BetaMlsSignedControlOutput>> signBetaMlsControl(
    BetaMlsSignControlRequest request,
  );

  Future<Result<BetaMlsSignedControlOutput>> verifyBetaMlsControl(
    BetaMlsVerifyControlRequest request,
  );

  Future<Result<Uint8List>> hashBetaMlsObject(BetaMlsHashObjectRequest request);
}
