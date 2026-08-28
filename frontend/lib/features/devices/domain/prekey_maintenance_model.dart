import 'dart:typed_data';

abstract final class PrekeyMaintenancePolicy {
  static const int classicalLowWatermark = 50;
  static const int classicalTarget = 150;
  static const int pqLowWatermark = 25;
  static const int pqTarget = 75;
  static const int maximumClassicalPool = 200;
  static const int maximumPqPool = 100;
  static const int signedPrekeyRotationDays = 7;
  static const int signedPrekeyRetentionThroughDay = 8;
}

final class PrekeyCounts {
  const PrekeyCounts({required this.classical, required this.postQuantum})
    : assert(classical >= 0),
      assert(classical <= PrekeyMaintenancePolicy.maximumClassicalPool),
      assert(postQuantum >= 0),
      assert(postQuantum <= PrekeyMaintenancePolicy.maximumPqPool);

  final int classical;
  final int postQuantum;

  int get classicalReplenishment =>
      classical < PrekeyMaintenancePolicy.classicalLowWatermark
      ? PrekeyMaintenancePolicy.classicalTarget - classical
      : 0;

  int get pqReplenishment =>
      postQuantum < PrekeyMaintenancePolicy.pqLowWatermark
      ? PrekeyMaintenancePolicy.pqTarget - postQuantum
      : 0;

  bool get needsReplenishment =>
      classicalReplenishment != 0 || pqReplenishment != 0;
}

final class PrekeyUploadEntry {
  PrekeyUploadEntry.classical({
    required this.keyId,
    required Uint8List publicKey,
  }) : isPostQuantum = false,
       publicKey = _copyPublicKey(publicKey, 32) {
    _checkKeyId(keyId);
  }

  PrekeyUploadEntry.postQuantum({
    required this.keyId,
    required Uint8List publicKey,
  }) : isPostQuantum = true,
       publicKey = _copyPublicKey(publicKey, 1184) {
    _checkKeyId(keyId);
  }

  final int keyId;
  final bool isPostQuantum;
  final Uint8List publicKey;

  @override
  String toString() => 'PrekeyUploadEntry(<redacted>)';
}

final class SignedPrekeyUpload {
  SignedPrekeyUpload.classical({
    required this.keyId,
    required Uint8List publicKey,
    required Uint8List signature,
  }) : isPostQuantum = false,
       publicKey = _copyPublicKey(publicKey, 32),
       signature = _copyPublicKey(signature, 64) {
    _checkKeyId(keyId);
  }

  SignedPrekeyUpload.postQuantum({
    required this.keyId,
    required Uint8List publicKey,
    required Uint8List signature,
  }) : isPostQuantum = true,
       publicKey = _copyPublicKey(publicKey, 1184),
       signature = _copyPublicKey(signature, 64) {
    _checkKeyId(keyId);
  }

  final int keyId;
  final bool isPostQuantum;
  final Uint8List publicKey;
  final Uint8List signature;

  @override
  String toString() => 'SignedPrekeyUpload(<redacted>)';
}

/// The signed classical/PQ prekeys, cross-signature, and bundle version are one
/// indivisible rotation projection. There is no constructor for a partial rotation.
final class SignedPrekeyRotationUpload {
  SignedPrekeyRotationUpload({
    required this.classical,
    required this.postQuantum,
    required Uint8List crossSignature,
    required this.bundleVersion,
  }) : crossSignature = _copyPublicKey(crossSignature, 64) {
    if (classical.isPostQuantum ||
        !postQuantum.isPostQuantum ||
        bundleVersion <= 0 ||
        bundleVersion > 0xffffffff) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final SignedPrekeyUpload classical;
  final SignedPrekeyUpload postQuantum;
  final Uint8List crossSignature;
  final int bundleVersion;

  @override
  String toString() => 'SignedPrekeyRotationUpload(<redacted>)';
}

/// Exact public upload projection paired with native-owned pending private state.
final class PrekeyUploadProjection {
  PrekeyUploadProjection({
    required List<PrekeyUploadEntry> classicalOneTimePrekeys,
    required List<PrekeyUploadEntry> pqOneTimePrekeys,
    this.rotation,
  }) : classicalOneTimePrekeys = List.unmodifiable(classicalOneTimePrekeys),
       pqOneTimePrekeys = List.unmodifiable(pqOneTimePrekeys) {
    if (this.classicalOneTimePrekeys.length >
            PrekeyMaintenancePolicy.maximumClassicalPool ||
        this.pqOneTimePrekeys.length > PrekeyMaintenancePolicy.maximumPqPool ||
        this.classicalOneTimePrekeys.any((value) => value.isPostQuantum) ||
        this.pqOneTimePrekeys.any((value) => !value.isPostQuantum) ||
        !_uniqueIds(this.classicalOneTimePrekeys) ||
        !_uniqueIds(this.pqOneTimePrekeys) ||
        (this.classicalOneTimePrekeys.isEmpty &&
            this.pqOneTimePrekeys.isEmpty &&
            rotation == null)) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final List<PrekeyUploadEntry> classicalOneTimePrekeys;
  final List<PrekeyUploadEntry> pqOneTimePrekeys;
  final SignedPrekeyRotationUpload? rotation;

  @override
  String toString() => 'PrekeyUploadProjection(<redacted>)';
}

enum PrekeyMaintenanceStage {
  prepared,
  uploadAcceptedAwaitingDeviceLogPreparation,
  deviceLogPrepared,
}

final class PreparedRotationDeviceLog {
  PreparedRotationDeviceLog({
    required this.expectedSequence,
    required Uint8List previousHeadHash,
    required Uint8List exactRecord,
  }) : previousHeadHash = _copyPublicKey(previousHeadHash, 32),
       exactRecord = _copyPublicKey(exactRecord, 256) {
    if (expectedSequence < 0) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final int expectedSequence;
  final Uint8List previousHeadHash;
  final Uint8List exactRecord;

  @override
  String toString() => 'PreparedRotationDeviceLog(<redacted>)';
}

/// A durable exact-retry plan. It must be stored before [upload] is attempted.
final class PrekeyMaintenancePlan {
  PrekeyMaintenancePlan({
    required this.deviceId,
    required this.expectedStateRevision,
    required this.preparedUnixDay,
    required this.bundleVersion,
    required this.currentSignedPrekeyCreatedUnixDay,
    required Uint8List batchId,
    required Uint8List nativeUploadProjection,
    required Uint8List pendingDeviceState,
    required this.upload,
    this.stage = PrekeyMaintenanceStage.prepared,
    this.rotationDeviceLog,
  }) : batchId = _copyPublicKey(batchId, 16),
       nativeUploadProjection = _copyOpaque(nativeUploadProjection),
       pendingDeviceState = _copyOpaque(pendingDeviceState) {
    if (!_uuid.hasMatch(deviceId) ||
        expectedStateRevision <= 0 ||
        preparedUnixDay < 0 ||
        bundleVersion <= 0 ||
        bundleVersion > 0xffffffff ||
        currentSignedPrekeyCreatedUnixDay < 0 ||
        currentSignedPrekeyCreatedUnixDay > preparedUnixDay ||
        (upload.rotation != null &&
            upload.rotation!.bundleVersion != bundleVersion) ||
        (stage != PrekeyMaintenanceStage.prepared && upload.rotation == null) ||
        ((stage == PrekeyMaintenanceStage.deviceLogPrepared) !=
            (rotationDeviceLog != null))) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final String deviceId;
  final int expectedStateRevision;
  final int preparedUnixDay;
  final int bundleVersion;

  /// Authoritative native value for the active atomic X25519/ML-KEM signed pair.
  /// Database defaults are never allowed to override this value.
  final int currentSignedPrekeyCreatedUnixDay;
  final Uint8List batchId;
  final Uint8List nativeUploadProjection;
  final Uint8List pendingDeviceState;
  final PrekeyUploadProjection upload;
  final PrekeyMaintenanceStage stage;
  final PreparedRotationDeviceLog? rotationDeviceLog;

  bool get rotatesSignedPrekeys => upload.rotation != null;

  PrekeyMaintenancePlan awaitingDeviceLogPreparation() => PrekeyMaintenancePlan(
    deviceId: deviceId,
    expectedStateRevision: expectedStateRevision,
    preparedUnixDay: preparedUnixDay,
    bundleVersion: bundleVersion,
    currentSignedPrekeyCreatedUnixDay: currentSignedPrekeyCreatedUnixDay,
    batchId: batchId,
    nativeUploadProjection: nativeUploadProjection,
    pendingDeviceState: pendingDeviceState,
    upload: upload,
    stage: PrekeyMaintenanceStage.uploadAcceptedAwaitingDeviceLogPreparation,
  );

  PrekeyMaintenancePlan withPreparedDeviceLog(
    PreparedRotationDeviceLog deviceLog,
  ) => PrekeyMaintenancePlan(
    deviceId: deviceId,
    expectedStateRevision: expectedStateRevision,
    preparedUnixDay: preparedUnixDay,
    bundleVersion: bundleVersion,
    currentSignedPrekeyCreatedUnixDay: currentSignedPrekeyCreatedUnixDay,
    batchId: batchId,
    nativeUploadProjection: nativeUploadProjection,
    pendingDeviceState: pendingDeviceState,
    upload: upload,
    stage: PrekeyMaintenanceStage.deviceLogPrepared,
    rotationDeviceLog: deviceLog,
  );

  @override
  String toString() =>
      'PrekeyMaintenancePlan(stage: ${stage.name}, <redacted>)';
}

final class PrekeyMaintenanceContext {
  PrekeyMaintenanceContext({
    required this.deviceId,
    required Uint8List userId,
    required Uint8List rawDeviceId,
    required Uint8List opaqueDeviceState,
    required Uint8List opaqueIdentityState,
    required this.stateRevision,
    required this.bundleVersion,
    required this.lastSignedPrekeyRotationUnixDay,
  }) : userId = _copyPublicKey(userId, 16),
       rawDeviceId = _copyPublicKey(rawDeviceId, 16),
       opaqueDeviceState = _copyOpaque(opaqueDeviceState),
       opaqueIdentityState = _copyOpaque(opaqueIdentityState) {
    if (!_uuid.hasMatch(deviceId) ||
        stateRevision <= 0 ||
        bundleVersion <= 0 ||
        bundleVersion > 0xffffffff ||
        lastSignedPrekeyRotationUnixDay < 0) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final String deviceId;
  final Uint8List userId;
  final Uint8List rawDeviceId;
  final Uint8List opaqueDeviceState;
  final Uint8List opaqueIdentityState;
  final int stateRevision;
  final int bundleVersion;
  final int lastSignedPrekeyRotationUnixDay;

  bool rotationDue(int unixDay) =>
      unixDay - lastSignedPrekeyRotationUnixDay >=
      PrekeyMaintenancePolicy.signedPrekeyRotationDays;

  @override
  String toString() => 'PrekeyMaintenanceContext(<redacted>)';
}

final class PrekeyMaintenanceReport {
  const PrekeyMaintenanceReport({
    required this.counts,
    required this.uploaded,
    required this.rotated,
  });

  final PrekeyCounts counts;
  final bool uploaded;
  final bool rotated;
}

final class ErasedSignedPrekeyPair {
  const ErasedSignedPrekeyPair({
    required this.classicalSignedPrekeyId,
    required this.pqSignedPrekeyId,
  }) : assert(classicalSignedPrekeyId >= 0),
       assert(classicalSignedPrekeyId <= 0x7fffffff),
       assert(pqSignedPrekeyId >= 0),
       assert(pqSignedPrekeyId <= 0x7fffffff);

  final int classicalSignedPrekeyId;
  final int pqSignedPrekeyId;
}

final class PrekeyCommitResult {
  PrekeyCommitResult({
    required Uint8List nextDeviceState,
    required this.bundleVersion,
    required this.currentSignedPrekeyCreatedUnixDay,
  }) : nextDeviceState = _copyOpaque(nextDeviceState) {
    if (bundleVersion <= 0 ||
        bundleVersion > 0xffffffff ||
        currentSignedPrekeyCreatedUnixDay < 0) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final Uint8List nextDeviceState;
  final int bundleVersion;
  final int currentSignedPrekeyCreatedUnixDay;
}

final class PrekeyPruneResult {
  PrekeyPruneResult({
    required Uint8List nextDeviceState,
    required this.stateChanged,
    required this.bundleVersion,
    required this.currentSignedPrekeyCreatedUnixDay,
    required List<ErasedSignedPrekeyPair> erasedSignedPrekeys,
  }) : nextDeviceState = _copyOpaque(nextDeviceState),
       erasedSignedPrekeys = List.unmodifiable(erasedSignedPrekeys) {
    if (bundleVersion <= 0 ||
        bundleVersion > 0xffffffff ||
        currentSignedPrekeyCreatedUnixDay < 0 ||
        (!stateChanged && this.erasedSignedPrekeys.isNotEmpty)) {
      throw const PrekeyMaintenanceFormatException();
    }
  }

  final Uint8List nextDeviceState;
  final bool stateChanged;
  final int bundleVersion;
  final int currentSignedPrekeyCreatedUnixDay;
  final List<ErasedSignedPrekeyPair> erasedSignedPrekeys;
}

final class PrekeyMaintenanceFormatException implements Exception {
  const PrekeyMaintenanceFormatException();
}

Uint8List _copyPublicKey(Uint8List value, int length) {
  if (value.length != length) {
    throw const PrekeyMaintenanceFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyOpaque(Uint8List value) {
  if (value.isEmpty || value.length > 2 * 1024 * 1024) {
    throw const PrekeyMaintenanceFormatException();
  }
  return Uint8List.fromList(value);
}

void _checkKeyId(int value) {
  if (value < 0 || value > 0x7fffffff) {
    throw const PrekeyMaintenanceFormatException();
  }
}

bool _uniqueIds(List<PrekeyUploadEntry> values) =>
    values.map((value) => value.keyId).toSet().length == values.length;

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
