import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_key_package_model.dart';

/// Closed-beta KeyPackage maintenance with a durable pre-network checkpoint.
///
/// Consumable uploads are append-only in the current backend contract. An
/// ambiguous request is therefore never replayed; maintenance remains visibly
/// blocked until an explicit beta reset/reconciliation policy resolves it.
final class GroupKeyPackageMaintenanceService {
  const GroupKeyPackageMaintenanceService({
    required this.remote,
    required this.authentication,
    required this.crypto,
    required this.store,
    required this.clock,
  });

  final GroupKeyPackageRemotePort remote;
  final GroupKeyPackageAuthenticationPort authentication;
  final GroupMlsCryptoPort crypto;
  final GroupKeyPackageMaintenanceStore store;
  final TimeSource clock;

  Future<Result<GroupKeyPackageMaintenanceReport>> maintain({
    required String userId,
    required String deviceId,
  }) async {
    final pendingResult = await store.readPending(deviceId: deviceId);
    if (pendingResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final pending =
        (pendingResult as Success<GroupKeyPackagePreparedPlan?>).value;
    if (pending != null) {
      final resumed = await _resume(pending);
      return resumed.fold(
        onSuccess: (count) => Result.success(
          GroupKeyPackageMaintenanceReport(
            consumableCount: count,
            uploadedConsumables:
                pending.upload.kind == MlsKeyPackageKind.consumable
                ? pending.upload.wrappedKeyPackages.length
                : 0,
            uploadedLastResort:
                pending.upload.kind == MlsKeyPackageKind.lastResort,
          ),
        ),
        onFailure: Result.failure,
      );
    }

    final countResult = await remote.fetchConsumableCount(deviceId: deviceId);
    if (countResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    var consumableCount = (countResult as Success<int>).value;
    if (consumableCount < 0 ||
        consumableCount >
            GroupKeyPackageMaintenancePolicy.maximumConsumablePool) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }

    var contextResult = await store.readGenerationContext(deviceId: deviceId);
    if (contextResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    var context =
        (contextResult as Success<GroupKeyPackageGenerationContext>).value;
    final consumablesToGenerate =
        consumableCount <
            GroupKeyPackageMaintenancePolicy.consumableLowWatermark
        ? GroupKeyPackageMaintenancePolicy.consumableTarget - consumableCount
        : 0;
    if (consumablesToGenerate == 0 && context.lastResortUploaded) {
      return Result.success(
        GroupKeyPackageMaintenanceReport(
          consumableCount: consumableCount,
          uploadedConsumables: 0,
          uploadedLastResort: false,
        ),
      );
    }

    final evidenceResult = await authentication.authenticateCurrentDevice(
      userId: userId,
      deviceId: deviceId,
    );
    if (evidenceResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final evidence =
        (evidenceResult as Success<GroupKeyPackageAuthenticationEvidence>)
            .value;
    var uploadedConsumables = 0;
    if (consumablesToGenerate != 0) {
      final uploaded = await _generatePersistAndResume(
        context: context,
        evidence: evidence,
        count: consumablesToGenerate,
        kind: MlsKeyPackageKind.consumable,
      );
      if (uploaded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      consumableCount = (uploaded as Success<int>).value;
      uploadedConsumables = consumablesToGenerate;
      contextResult = await store.readGenerationContext(deviceId: deviceId);
      if (contextResult case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      context =
          (contextResult as Success<GroupKeyPackageGenerationContext>).value;
    }

    var uploadedLastResort = false;
    if (!context.lastResortUploaded) {
      final uploaded = await _generatePersistAndResume(
        context: context,
        evidence: evidence,
        count: 1,
        kind: MlsKeyPackageKind.lastResort,
      );
      if (uploaded case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      consumableCount = (uploaded as Success<int>).value;
      uploadedLastResort = true;
    }
    return Result.success(
      GroupKeyPackageMaintenanceReport(
        consumableCount: consumableCount,
        uploadedConsumables: uploadedConsumables,
        uploadedLastResort: uploadedLastResort,
      ),
    );
  }

  Future<Result<int>> _generatePersistAndResume({
    required GroupKeyPackageGenerationContext context,
    required GroupKeyPackageAuthenticationEvidence evidence,
    required int count,
    required MlsKeyPackageKind kind,
  }) async {
    final generatedResult = await crypto.generateKeyPackages(
      MlsKeyPackageGenerationRequest(
        opaqueDeviceState: context.opaqueDeviceState,
        migrationUnixDay:
            clock.now().toUtc().millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay,
        localVerifiedBundleRequest: evidence.localVerifiedBundleRequest,
        priorOpaqueKeyPackageState: context.sealedKeyPackageState,
        count: count,
        kind: kind,
      ),
    );
    if (generatedResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final generated =
        (generatedResult as Success<GeneratedMlsKeyPackages>).value;
    if (generated.kind != kind ||
        generated.wrappedKeyPackages.length != count) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.integrityCheckFailed),
      );
    }
    final plan = GroupKeyPackagePreparedPlan(
      deviceId: context.deviceId,
      expectedStateRevision: context.keyPackageStateRevision,
      nextSealedKeyPackageState: generated.opaqueKeyPackageState,
      upload: GroupKeyPackageUpload(
        kind: kind,
        wrappedKeyPackages: generated.wrappedKeyPackages,
      ),
    );
    final persisted = await store.persistPrepared(plan);
    if (persisted case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return _resume(plan);
  }

  Future<Result<int>> _resume(GroupKeyPackagePreparedPlan plan) async {
    if (plan.stage == GroupKeyPackagePlanStage.ambiguous) {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }
    if (plan.stage == GroupKeyPackagePlanStage.attemptStarted) {
      final marked = await store.moveStage(
        plan: plan,
        nextStage: GroupKeyPackagePlanStage.ambiguous,
      );
      if (marked case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.policyBlocked),
      );
    }

    var attempt = plan;
    if (plan.upload.kind == MlsKeyPackageKind.consumable) {
      final started = await store.moveStage(
        plan: plan,
        nextStage: GroupKeyPackagePlanStage.attemptStarted,
      );
      if (started case FailureResult(failure: final failure)) {
        return Result.failure(failure);
      }
      attempt = plan.withStage(GroupKeyPackagePlanStage.attemptStarted);
    }
    final uploaded = await remote.upload(
      deviceId: plan.deviceId,
      upload: plan.upload,
    );
    if (uploaded case FailureResult(failure: final failure)) {
      if (plan.upload.kind == MlsKeyPackageKind.consumable) {
        final nextStage =
            failure is TransportFailure || failure is CancellationFailure
            ? GroupKeyPackagePlanStage.ambiguous
            : GroupKeyPackagePlanStage.prepared;
        final checkpoint = await store.moveStage(
          plan: attempt,
          nextStage: nextStage,
        );
        if (checkpoint case FailureResult(failure: final checkpointFailure)) {
          return Result.failure(checkpointFailure);
        }
      }
      return Result.failure(failure);
    }
    final completed = await store.complete(attempt);
    if (completed case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    return Result.success((uploaded as Success<int>).value);
  }
}
