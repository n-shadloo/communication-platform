import 'dart:typed_data';

enum MlsKeyPackageKind { consumable, lastResort }

final class BetaMlsAuthenticationInput {
  BetaMlsAuthenticationInput({
    required Uint8List opaqueDeviceState,
    required this.migrationUnixDay,
    required Uint8List localVerifiedBundleRequest,
    Iterable<Uint8List> additionalVerifiedBundleRequests = const [],
  }) : opaqueDeviceState = _copyBounded(opaqueDeviceState),
       localVerifiedBundleRequest = _copyBundle(localVerifiedBundleRequest),
       additionalVerifiedBundleRequests = List.unmodifiable(
         additionalVerifiedBundleRequests.map(_copyBundle),
       ) {
    if (migrationUnixDay < 0 ||
        migrationUnixDay > 0xffffffff ||
        this.additionalVerifiedBundleRequests.length >= 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List opaqueDeviceState;
  final int migrationUnixDay;
  final Uint8List localVerifiedBundleRequest;
  final List<Uint8List> additionalVerifiedBundleRequests;

  @override
  String toString() => 'BetaMlsAuthenticationInput(<redacted>)';
}

sealed class BetaMlsLifecycleRequest {
  const BetaMlsLifecycleRequest();

  BetaMlsAuthenticationInput get authentication;
}

final class BetaMlsCreateRequest extends BetaMlsLifecycleRequest {
  BetaMlsCreateRequest({
    required this.authentication,
    required Iterable<Uint8List> wrappedKeyPackages,
    required Uint8List authenticatedData,
  }) : wrappedKeyPackages = List.unmodifiable(
         wrappedKeyPackages.map(_copyWrappedKeyPackage),
       ),
       authenticatedData = _copyEventData(authenticatedData) {
    if (this.wrappedKeyPackages.isEmpty ||
        this.wrappedKeyPackages.length >= 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  @override
  final BetaMlsAuthenticationInput authentication;
  final List<Uint8List> wrappedKeyPackages;
  final Uint8List authenticatedData;
}

final class BetaMlsJoinRequest extends BetaMlsLifecycleRequest {
  BetaMlsJoinRequest({
    required this.authentication,
    required Uint8List sealedKeyPackageState,
    required Uint8List welcome,
  }) : sealedKeyPackageState = _copyBounded(sealedKeyPackageState),
       welcome = _copyMlsObject(welcome);

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedKeyPackageState;
  final Uint8List welcome;
}

final class BetaMlsAddMembersRequest extends BetaMlsLifecycleRequest {
  BetaMlsAddMembersRequest({
    required this.authentication,
    required Uint8List sealedGroupState,
    required Iterable<Uint8List> wrappedKeyPackages,
    required Uint8List authenticatedData,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       wrappedKeyPackages = List.unmodifiable(
         wrappedKeyPackages.map(_copyWrappedKeyPackage),
       ),
       authenticatedData = _copyEventData(authenticatedData) {
    if (this.wrappedKeyPackages.isEmpty ||
        this.wrappedKeyPackages.length >= 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedGroupState;
  final List<Uint8List> wrappedKeyPackages;
  final Uint8List authenticatedData;
}

final class BetaMlsRemoveMembersRequest extends BetaMlsLifecycleRequest {
  BetaMlsRemoveMembersRequest({
    required this.authentication,
    required Uint8List sealedGroupState,
    required Iterable<Uint8List> targetUserIds,
    required Uint8List authenticatedData,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       targetUserIds = List.unmodifiable(targetUserIds.map(_copyUserId)),
       authenticatedData = _copyEventData(authenticatedData) {
    if (this.targetUserIds.isEmpty || this.targetUserIds.length >= 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedGroupState;
  final List<Uint8List> targetUserIds;
  final Uint8List authenticatedData;
}

final class BetaMlsSendApplicationRequest extends BetaMlsLifecycleRequest {
  BetaMlsSendApplicationRequest({
    required this.authentication,
    required Uint8List sealedGroupState,
    required Uint8List applicationData,
    required Uint8List authenticatedData,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       applicationData = _copyApplicationData(applicationData),
       authenticatedData = _copyEventData(authenticatedData);

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedGroupState;
  final Uint8List applicationData;
  final Uint8List authenticatedData;
}

final class BetaMlsProcessMessageRequest extends BetaMlsLifecycleRequest {
  BetaMlsProcessMessageRequest({
    required this.authentication,
    required Uint8List sealedGroupState,
    required Uint8List message,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       message = _copyMlsObject(message);

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedGroupState;
  final Uint8List message;
}

final class BetaMlsHashObjectRequest extends BetaMlsLifecycleRequest {
  BetaMlsHashObjectRequest({
    required this.authentication,
    required Uint8List object,
  }) : object = _copyMlsObject(object);

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List object;
}

enum BetaMlsPendingCommitKind { proposeUpdate, commitPendingProposals }

final class BetaMlsPendingCommitRequest extends BetaMlsLifecycleRequest {
  BetaMlsPendingCommitRequest({
    required this.authentication,
    required Uint8List sealedGroupState,
    required Uint8List authenticatedData,
    required this.kind,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       authenticatedData = _copyEventData(authenticatedData);

  @override
  final BetaMlsAuthenticationInput authentication;
  final Uint8List sealedGroupState;
  final Uint8List authenticatedData;
  final BetaMlsPendingCommitKind kind;
}

final class BetaMlsCommitOutput {
  BetaMlsCommitOutput({
    required Uint8List sealedGroupState,
    required Uint8List commit,
    required Uint8List commitDigest,
    required Iterable<Uint8List> authenticationBundleRequests,
    required Iterable<Uint8List> welcomes,
    required Uint8List groupInfo,
    required Uint8List groupId,
    required this.epoch,
    required Uint8List exporterConfirmation,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       commit = _copyMlsObject(commit),
       commitDigest = _copyDigest(commitDigest),
       authenticationBundleRequests = List.unmodifiable(
         authenticationBundleRequests.map(_copyBundle),
       ),
       welcomes = List.unmodifiable(welcomes.map(_copyMlsObject)),
       groupInfo = _copyMlsObject(groupInfo),
       groupId = _copyGroupId(groupId),
       exporterConfirmation = _copyDigest(exporterConfirmation) {
    if (this.authenticationBundleRequests.isEmpty ||
        this.authenticationBundleRequests.length > 50 ||
        this.welcomes.length >= 50 ||
        epoch < 0) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List sealedGroupState;
  final Uint8List commit;
  final Uint8List commitDigest;
  final List<Uint8List> authenticationBundleRequests;
  final List<Uint8List> welcomes;
  final Uint8List groupInfo;
  final Uint8List groupId;
  final int epoch;
  final Uint8List exporterConfirmation;
}

final class BetaMlsJoinOutput {
  BetaMlsJoinOutput({
    required Uint8List sealedGroupState,
    required Uint8List sealedKeyPackageState,
    required Uint8List groupId,
    required this.epoch,
    required Iterable<BetaMlsRosterDevice> roster,
    required Uint8List exporterConfirmation,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       sealedKeyPackageState = _copyBounded(sealedKeyPackageState),
       groupId = _copyGroupId(groupId),
       roster = List.unmodifiable(roster),
       exporterConfirmation = _copyDigest(exporterConfirmation) {
    if (epoch < 0 || this.roster.isEmpty || this.roster.length > 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List sealedGroupState;
  final Uint8List sealedKeyPackageState;
  final Uint8List groupId;
  final int epoch;
  final List<BetaMlsRosterDevice> roster;
  final Uint8List exporterConfirmation;
}

final class BetaMlsRosterDevice {
  BetaMlsRosterDevice({required Uint8List userId, required Uint8List deviceId})
    : userId = _copyUserId(userId),
      deviceId = _copyUserId(deviceId);

  final Uint8List userId;
  final Uint8List deviceId;
}

final class BetaMlsMessageOutput {
  BetaMlsMessageOutput({
    required Uint8List sealedGroupState,
    required Uint8List message,
    required Uint8List groupId,
    required this.epoch,
    required Uint8List exporterConfirmation,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       message = _copyMlsObject(message),
       groupId = _copyGroupId(groupId),
       exporterConfirmation = _copyDigest(exporterConfirmation) {
    if (epoch < 0) throw const MlsKeyPackageFormatException();
  }

  final Uint8List sealedGroupState;
  final Uint8List message;
  final Uint8List groupId;
  final int epoch;
  final Uint8List exporterConfirmation;
}

enum BetaMlsReceivedKind { application, commit, proposal, groupInfo }

final class BetaMlsProcessedMessage {
  BetaMlsProcessedMessage({
    required Uint8List sealedGroupState,
    required Uint8List messageDigest,
    required this.kind,
    required this.senderLeafIndex,
    required Uint8List senderUserId,
    required Uint8List senderDeviceId,
    required Uint8List data,
    required Uint8List authenticatedData,
    required Uint8List groupId,
    required this.epoch,
    required Uint8List exporterConfirmation,
  }) : sealedGroupState = _copyBounded(sealedGroupState),
       messageDigest = _copyDigest(messageDigest),
       senderUserId = _copySenderId(senderUserId, kind),
       senderDeviceId = _copySenderId(senderDeviceId, kind),
       data = _copyOptionalData(data),
       authenticatedData = _copyOptionalData(authenticatedData),
       groupId = _copyGroupId(groupId),
       exporterConfirmation = _copyDigest(exporterConfirmation) {
    if (senderLeafIndex < 0 || senderLeafIndex > 0xffffffff || epoch < 0) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List sealedGroupState;
  final Uint8List messageDigest;
  final BetaMlsReceivedKind kind;
  final int senderLeafIndex;
  final Uint8List senderUserId;
  final Uint8List senderDeviceId;
  final Uint8List data;
  final Uint8List authenticatedData;
  final Uint8List groupId;
  final int epoch;
  final Uint8List exporterConfirmation;
}

final class BetaMlsControlMetadata {
  BetaMlsControlMetadata({
    required this.name,
    this.description = '',
    this.photoCapability,
  }) {
    if (name.isEmpty ||
        name.trim() != name ||
        name.runes.length > 100 ||
        description.trim() != description ||
        description.runes.length > 1000 ||
        (photoCapability != null &&
            (photoCapability!.isEmpty ||
                photoCapability!.runes.length > 1024))) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final String name;
  final String description;
  final String? photoCapability;
}

final class BetaMlsControlMember {
  BetaMlsControlMember({
    required Uint8List userId,
    required this.displayName,
    required this.role,
    required this.membership,
    required this.verified,
    required Iterable<Uint8List> deviceIds,
  }) : userId = _copyUserId(userId),
       deviceIds = List.unmodifiable(deviceIds.map(_copyUserId)) {
    if (displayName.isEmpty ||
        displayName.runes.length > 256 ||
        role < 0 ||
        role > 2 ||
        membership < 0 ||
        membership > 2 ||
        this.deviceIds.isEmpty ||
        this.deviceIds.length > 50 ||
        _byteKeys(this.deviceIds).length != this.deviceIds.length) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List userId;
  final String displayName;
  final int role;
  final int membership;
  final bool verified;
  final List<Uint8List> deviceIds;
}

sealed class BetaMlsControlOperationInput {
  const BetaMlsControlOperationInput();

  int get code;
  bool get changesMembership;
}

final class BetaMlsCreateControlInput extends BetaMlsControlOperationInput {
  BetaMlsCreateControlInput({
    required this.metadata,
    required this.invitationPolicy,
    required this.historyPolicy,
    required Iterable<BetaMlsControlMember> members,
  }) : members = List.unmodifiable(members) {
    if (invitationPolicy < 0 ||
        invitationPolicy > 2 ||
        historyPolicy < 0 ||
        historyPolicy > 1 ||
        this.members.isEmpty ||
        this.members.length > 50 ||
        _byteKeys(this.members.map((value) => value.userId)).length !=
            this.members.length) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final BetaMlsControlMetadata metadata;
  final int invitationPolicy;
  final int historyPolicy;
  final List<BetaMlsControlMember> members;

  @override
  int get code => 1;
  @override
  bool get changesMembership => true;
}

final class BetaMlsUpdateMetadataControlInput
    extends BetaMlsControlOperationInput {
  const BetaMlsUpdateMetadataControlInput(this.metadata);

  final BetaMlsControlMetadata metadata;
  @override
  int get code => 2;
  @override
  bool get changesMembership => false;
}

final class BetaMlsUpdatePoliciesControlInput
    extends BetaMlsControlOperationInput {
  BetaMlsUpdatePoliciesControlInput({
    required this.invitationPolicy,
    required this.historyPolicy,
  }) {
    if (invitationPolicy < 0 ||
        invitationPolicy > 2 ||
        historyPolicy < 0 ||
        historyPolicy > 1) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final int invitationPolicy;
  final int historyPolicy;
  @override
  int get code => 3;
  @override
  bool get changesMembership => false;
}

final class BetaMlsInviteControlInput extends BetaMlsControlOperationInput {
  BetaMlsInviteControlInput(Iterable<BetaMlsControlMember> members)
    : members = List.unmodifiable(members) {
    if (this.members.isEmpty ||
        this.members.length > 50 ||
        _byteKeys(this.members.map((value) => value.userId)).length !=
            this.members.length) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final List<BetaMlsControlMember> members;
  @override
  int get code => 4;
  @override
  bool get changesMembership => true;
}

final class BetaMlsRemoveControlInput extends BetaMlsControlOperationInput {
  BetaMlsRemoveControlInput(Uint8List targetUserId)
    : targetUserId = _copyUserId(targetUserId);

  final Uint8List targetUserId;
  @override
  int get code => 5;
  @override
  bool get changesMembership => true;
}

final class BetaMlsLeaveControlInput extends BetaMlsControlOperationInput {
  const BetaMlsLeaveControlInput();
  @override
  int get code => 6;
  @override
  bool get changesMembership => true;
}

final class BetaMlsChangeRoleControlInput extends BetaMlsControlOperationInput {
  BetaMlsChangeRoleControlInput({
    required Uint8List targetUserId,
    required this.role,
  }) : targetUserId = _copyUserId(targetUserId) {
    if (role < 0 || role > 2) throw const MlsKeyPackageFormatException();
  }

  final Uint8List targetUserId;
  final int role;
  @override
  int get code => 7;
  @override
  bool get changesMembership => false;
}

final class BetaMlsTransferOwnershipControlInput
    extends BetaMlsControlOperationInput {
  BetaMlsTransferOwnershipControlInput(Uint8List targetUserId)
    : targetUserId = _copyUserId(targetUserId);

  final Uint8List targetUserId;
  @override
  int get code => 8;
  @override
  bool get changesMembership => false;
}

final class BetaMlsControlDescriptor {
  BetaMlsControlDescriptor({
    required Uint8List eventId,
    required Uint8List groupId,
    required this.revision,
    Uint8List? previousControlStateHash,
    required this.mlsEpoch,
    Uint8List? mlsCommitHash,
    required this.createdMs,
    required this.operation,
  }) : eventId = _copyEventId(eventId),
       groupId = _copyGroupId(groupId),
       previousControlStateHash = previousControlStateHash == null
           ? null
           : _copyDigest(previousControlStateHash),
       mlsCommitHash = mlsCommitHash == null
           ? null
           : _copyDigest(mlsCommitHash) {
    if (revision < 1 ||
        revision > 0xffffffff ||
        mlsEpoch < 0 ||
        createdMs < 0 ||
        operation.changesMembership != (this.mlsCommitHash != null) ||
        (operation is BetaMlsCreateControlInput) !=
            (revision == 1 && this.previousControlStateHash == null)) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List eventId;
  final Uint8List groupId;
  final int revision;
  final Uint8List? previousControlStateHash;
  final int mlsEpoch;
  final Uint8List? mlsCommitHash;
  final int createdMs;
  final BetaMlsControlOperationInput operation;
}

final class BetaMlsSignControlRequest extends BetaMlsLifecycleRequest {
  const BetaMlsSignControlRequest({
    required this.authentication,
    required this.descriptor,
  });

  @override
  final BetaMlsAuthenticationInput authentication;
  final BetaMlsControlDescriptor descriptor;
}

final class BetaMlsVerifyControlRequest extends BetaMlsLifecycleRequest {
  BetaMlsVerifyControlRequest({
    required this.authentication,
    required this.descriptor,
    required Uint8List signerUserId,
    required Uint8List signerDeviceId,
    required Uint8List signedPayload,
  }) : signerUserId = _copyUserId(signerUserId),
       signerDeviceId = _copyUserId(signerDeviceId),
       signedPayload = _copyEventData(signedPayload) {
    if (this.signedPayload.isEmpty) {
      throw const MlsKeyPackageFormatException();
    }
  }

  @override
  final BetaMlsAuthenticationInput authentication;
  final BetaMlsControlDescriptor descriptor;
  final Uint8List signerUserId;
  final Uint8List signerDeviceId;
  final Uint8List signedPayload;
}

final class BetaMlsSignedControlOutput {
  BetaMlsSignedControlOutput({
    required Uint8List canonicalBytes,
    required Uint8List signature,
    required Uint8List controlStateHash,
    required Uint8List signedPayload,
    required Uint8List signerUserId,
    required Uint8List signerDeviceId,
  }) : canonicalBytes = _copyEventData(canonicalBytes),
       signature = _copySignature(signature),
       controlStateHash = _copyDigest(controlStateHash),
       signedPayload = _copyEventData(signedPayload),
       signerUserId = _copyUserId(signerUserId),
       signerDeviceId = _copyUserId(signerDeviceId) {
    if (this.canonicalBytes.isEmpty || this.signedPayload.isEmpty) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List canonicalBytes;
  final Uint8List signature;
  final Uint8List controlStateHash;
  final Uint8List signedPayload;
  final Uint8List signerUserId;
  final Uint8List signerDeviceId;
}

/// Inputs for one authenticated native KeyPackage generation transaction.
///
/// Bundle request bytes are native-verified Authentication Service evidence.
/// Device and KeyPackage states remain opaque and must be stored atomically by
/// the caller before any upload.
final class MlsKeyPackageGenerationRequest {
  MlsKeyPackageGenerationRequest({
    required Uint8List opaqueDeviceState,
    required this.migrationUnixDay,
    required Uint8List localVerifiedBundleRequest,
    Iterable<Uint8List> additionalVerifiedBundleRequests = const [],
    Uint8List? priorOpaqueKeyPackageState,
    required this.count,
    required this.kind,
  }) : opaqueDeviceState = _copyBounded(opaqueDeviceState),
       localVerifiedBundleRequest = _copyBundle(localVerifiedBundleRequest),
       additionalVerifiedBundleRequests = List.unmodifiable(
         additionalVerifiedBundleRequests.map(_copyBundle),
       ),
       priorOpaqueKeyPackageState = priorOpaqueKeyPackageState == null
           ? null
           : _copyBounded(priorOpaqueKeyPackageState) {
    if (migrationUnixDay < 0 ||
        migrationUnixDay > 0xffffffff ||
        count < 1 ||
        count > 100 ||
        (kind == MlsKeyPackageKind.lastResort && count != 1) ||
        this.additionalVerifiedBundleRequests.length >= 50) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final Uint8List opaqueDeviceState;
  final int migrationUnixDay;
  final Uint8List localVerifiedBundleRequest;
  final List<Uint8List> additionalVerifiedBundleRequests;
  final Uint8List? priorOpaqueKeyPackageState;
  final int count;
  final MlsKeyPackageKind kind;

  @override
  String toString() => 'MlsKeyPackageGenerationRequest(<redacted>)';
}

final class GeneratedMlsKeyPackages {
  GeneratedMlsKeyPackages({
    required this.kind,
    required Uint8List opaqueKeyPackageState,
    required Iterable<Uint8List> wrappedKeyPackages,
  }) : opaqueKeyPackageState = _copyBounded(opaqueKeyPackageState),
       wrappedKeyPackages = List.unmodifiable(
         wrappedKeyPackages.map(_copyWrappedKeyPackage),
       ) {
    if (this.wrappedKeyPackages.isEmpty ||
        this.wrappedKeyPackages.length > 100 ||
        (kind == MlsKeyPackageKind.lastResort &&
            this.wrappedKeyPackages.length != 1)) {
      throw const MlsKeyPackageFormatException();
    }
  }

  final MlsKeyPackageKind kind;
  final Uint8List opaqueKeyPackageState;
  final List<Uint8List> wrappedKeyPackages;

  @override
  String toString() => 'GeneratedMlsKeyPackages(<redacted>)';
}

final class MlsKeyPackageFormatException implements Exception {
  const MlsKeyPackageFormatException();
}

Uint8List _copyBounded(Uint8List value) {
  if (value.isEmpty || value.length > 1024 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyBundle(Uint8List value) {
  if (value.length < 8 || value.length > 16 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copySenderId(Uint8List value, BetaMlsReceivedKind kind) {
  if (kind == BetaMlsReceivedKind.groupInfo && value.isEmpty) {
    return Uint8List(0);
  }
  return _copyUserId(value);
}

Uint8List _copyWrappedKeyPackage(Uint8List value) {
  if (value.length != 4096 && value.length != 16 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyEventData(Uint8List value) {
  if (value.length > 64 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyApplicationData(Uint8List value) {
  if (value.isEmpty || value.length > 256 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyMlsObject(Uint8List value) {
  if (value.isEmpty || value.length > 1024 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyOptionalData(Uint8List value) {
  if (value.length > 256 * 1024) {
    throw const MlsKeyPackageFormatException();
  }
  return Uint8List.fromList(value);
}

Uint8List _copyUserId(Uint8List value) {
  if (value.length != 16) throw const MlsKeyPackageFormatException();
  return Uint8List.fromList(value);
}

Uint8List _copyGroupId(Uint8List value) {
  if (value.length != 32) throw const MlsKeyPackageFormatException();
  return Uint8List.fromList(value);
}

Uint8List _copyDigest(Uint8List value) => _copyGroupId(value);

Uint8List _copyEventId(Uint8List value) => _copyUserId(value);

Uint8List _copySignature(Uint8List value) {
  if (value.length != 64) throw const MlsKeyPackageFormatException();
  return Uint8List.fromList(value);
}

Set<String> _byteKeys(Iterable<Uint8List> values) => {
  for (final value in values) value.join(','),
};
