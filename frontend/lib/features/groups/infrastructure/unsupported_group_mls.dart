import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';

final class UnsupportedGroupMlsCrypto implements GroupMlsCryptoPort {
  const UnsupportedGroupMlsCrypto();

  Future<Result<T>> _closed<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<PreparedGroupTransition>> prepareCreate(
    GroupCreationIntent intent,
  ) => _closed();

  @override
  Future<Result<PreparedGroupTransition>> prepareControl({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required GroupControlOperation operation,
    required String actorUserId,
    required String actorDeviceId,
    required int createdMs,
  }) => _closed();

  @override
  Future<Result<PreparedGroupTransition>> inspectIncomingControl({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required Uint8List mlsObject,
  }) => _closed();

  @override
  Future<Result<PreparedGroupMessage>> prepareApplicationMessage({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required String senderUserId,
    required String senderDeviceId,
    required String text,
    required int createdMs,
  }) => _closed();

  @override
  Future<Result<List<Uint8List>>> generateKeyPackages({required int count}) =>
      _closed();

  @override
  Future<Result<PreparedGroupTransition>> reconcileFork({
    required GroupState current,
    required Uint8List currentOpaqueMlsState,
    required List<Uint8List> siblingCommits,
  }) => _closed();
}
