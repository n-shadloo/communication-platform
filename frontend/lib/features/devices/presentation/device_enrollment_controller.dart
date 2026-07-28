import 'dart:typed_data';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/device_enrollment_coordinator.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum EnrollmentOperation {
  dormant,
  loading,
  retrying,
  restoring,
  confirming,
  reconciling,
  acknowledging,
  idle,
}

final class DeviceEnrollmentViewState {
  const DeviceEnrollmentViewState({
    required this.operation,
    this.journal,
    this.failure,
  });

  const DeviceEnrollmentViewState.dormant()
    : operation = EnrollmentOperation.dormant,
      journal = null,
      failure = null;

  final EnrollmentOperation operation;
  final EnrollmentJournal? journal;
  final Failure? failure;

  bool get isBusy =>
      operation != EnrollmentOperation.dormant &&
      operation != EnrollmentOperation.idle;

  bool get isMessagingWithheld => journal?.isMessagingWithheld ?? true;
}

final deviceEnrollmentCoordinatorProvider =
    Provider<DeviceEnrollmentCoordinator>(
      (ref) => throw StateError('Device enrollment is not installed.'),
    );

final deviceEnrollmentControllerProvider =
    NotifierProvider<DeviceEnrollmentController, DeviceEnrollmentViewState>(
      DeviceEnrollmentController.new,
    );

final class DeviceEnrollmentController
    extends Notifier<DeviceEnrollmentViewState> {
  String? _startedUserId;

  DeviceEnrollmentCoordinator get _coordinator =>
      ref.read(deviceEnrollmentCoordinatorProvider);

  @override
  DeviceEnrollmentViewState build() =>
      const DeviceEnrollmentViewState.dormant();

  Future<void> start(String userId) async {
    if (_startedUserId == userId) {
      return;
    }
    _startedUserId = userId;
    state = const DeviceEnrollmentViewState(
      operation: EnrollmentOperation.loading,
    );
    _apply(await _coordinator.loadOrStart(userId: userId));
  }

  Future<void> retry(String userId) async {
    if (state.isBusy) {
      return;
    }
    state = DeviceEnrollmentViewState(
      operation: EnrollmentOperation.retrying,
      journal: state.journal,
    );
    _apply(await _coordinator.retry(userId: userId));
  }

  Future<void> markRecoverySecretDisplayed(String userId) async {
    if (state.isBusy) {
      return;
    }
    _apply(await _coordinator.markRecoverySecretDisplayed(userId: userId));
  }

  Future<void> confirmRecoverySecret(String userId) async {
    if (state.isBusy) {
      return;
    }
    state = DeviceEnrollmentViewState(
      operation: EnrollmentOperation.confirming,
      journal: state.journal,
    );
    _apply(await _coordinator.confirmRecoverySecret(userId: userId));
  }

  Future<void> restoreIdentity(String userId, Uint8List recoverySecret) async {
    if (state.isBusy) {
      recoverySecret.fillRange(0, recoverySecret.length, 0);
      return;
    }
    state = DeviceEnrollmentViewState(
      operation: EnrollmentOperation.restoring,
      journal: state.journal,
    );
    _apply(
      await _coordinator.restoreWithRecoverySecret(
        userId: userId,
        recoverySecret: recoverySecret,
      ),
    );
  }

  Future<void> reconcile(String userId) async {
    if (state.isBusy) {
      return;
    }
    state = DeviceEnrollmentViewState(
      operation: EnrollmentOperation.reconciling,
      journal: state.journal,
    );
    _apply(await _coordinator.reconcileAmbiguousRegistration(userId: userId));
  }

  Future<bool> acceptSecurityNotice(String userId) async {
    if (state.isBusy) {
      return false;
    }
    state = DeviceEnrollmentViewState(
      operation: EnrollmentOperation.acknowledging,
      journal: state.journal,
    );
    final result = await _coordinator.acceptSecurityNotice(userId: userId);
    _apply(result);
    return result is Success<EnrollmentJournal>;
  }

  void _apply(Result<EnrollmentJournal> result) {
    state = result.fold(
      onSuccess: (journal) => DeviceEnrollmentViewState(
        operation: EnrollmentOperation.idle,
        journal: journal,
      ),
      onFailure: (failure) => DeviceEnrollmentViewState(
        operation: EnrollmentOperation.idle,
        journal: state.journal,
        failure: failure,
      ),
    );
  }
}
