import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';

/// Functional boundary for the reviewed Rust/OpenMLS implementation in piece 19.
///
/// Implementations return a complete next opaque state without mutating the durable
/// current state. The repository commits that state, its signed control/application
/// fact, projections, and outbound work in one transaction.
abstract interface class GroupMlsCryptoPort {
  Future<Result<PreparedGroupTransition>> prepareCreate(
    GroupCreationIntent intent,
  );

  Future<Result<PreparedGroupTransition>> prepareControl({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required GroupControlOperation operation,
    required String actorUserId,
    required String actorDeviceId,
    required int createdMs,
  });

  Future<Result<PreparedGroupTransition>> inspectIncomingControl({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required Uint8List mlsObject,
  });

  Future<Result<PreparedGroupMessage>> prepareApplicationMessage({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required String senderUserId,
    required String senderDeviceId,
    required String text,
    required int createdMs,
  });

  /// Piece 19 implements this only after all profile gates pass.
  Future<Result<List<Uint8List>>> generateKeyPackages({required int count});

  /// Canonical sibling-commit re-proposal remains crypto-core owned.
  Future<Result<PreparedGroupTransition>> reconcileFork({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required List<Uint8List> siblingCommits,
  });
}

abstract interface class GroupRepositoryPort {
  Stream<GroupState?> watchGroup(String groupId);

  Stream<List<GroupMessage>> watchMessages(String groupId);

  Future<Result<GroupState?>> readGroup(String groupId);

  Future<Result<Uint8List?>> readOpaqueMlsState(String groupId);

  Future<Result<void>> commitTransition({
    required GroupState? expectedPrevious,
    required GroupState next,
    required PreparedGroupTransition prepared,
    required bool developmentPreviewOnly,
  });

  Future<Result<void>> commitMessage({
    required GroupState expectedGroup,
    required PreparedGroupMessage prepared,
    required bool developmentPreviewOnly,
  });

  Future<Result<void>> quarantine(GroupQuarantineRecord record);
}
