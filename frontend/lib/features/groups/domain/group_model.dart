import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

enum GroupRole { owner, admin, member }

enum GroupMembershipState { active, removed, left }

enum GroupInvitationPolicy { ownerOnly, ownerAndAdmins, allMembers }

enum GroupHistorySharingPolicy { reshareAvailable, newMessagesOnly }

enum GroupLifecycle {
  active,
  membershipUpdating,
  removed,
  left,
  queueGapRejoinRequired,
  forkQuarantined,
  controlQuarantined,
}

enum GroupQuarantineReason {
  siblingCommit,
  staleRevision,
  brokenControlChain,
  malformedControl,
  unauthenticatedControl,
  unauthorizedControl,
  invalidMembership,
}

enum GroupPermission {
  viewHistory,
  sendMessages,
  inviteMembers,
  removeMembers,
  editMetadata,
  editInvitationPolicy,
  editHistorySharingPolicy,
  changeRoles,
  transferOwnership,
  pinMessages,
  leave,
}

final class GroupMetadata {
  const GroupMetadata({
    required this.name,
    this.description = '',
    this.photoCapability,
  });

  static const maximumNameScalars = 100;
  static const maximumDescriptionScalars = 1000;

  final String name;
  final String description;
  final String? photoCapability;

  bool get isValid {
    final normalizedName = name.trim();
    return normalizedName.isNotEmpty &&
        normalizedName.runes.length <= maximumNameScalars &&
        description.runes.length <= maximumDescriptionScalars &&
        (photoCapability == null || photoCapability!.trim().isNotEmpty);
  }

  GroupMetadata normalized() => GroupMetadata(
    name: name.trim(),
    description: description.trim(),
    photoCapability: photoCapability?.trim(),
  );

  @override
  bool operator ==(Object other) =>
      other is GroupMetadata &&
      other.name == name &&
      other.description == description &&
      other.photoCapability == photoCapability;

  @override
  int get hashCode => Object.hash(name, description, photoCapability);
}

final class GroupMember {
  GroupMember({
    required this.userId,
    required this.displayName,
    required this.role,
    this.membership = GroupMembershipState.active,
    this.verified = false,
    Iterable<String> deviceIds = const [],
  }) : deviceIds = List.unmodifiable(_sortedUnique(deviceIds));

  final String userId;
  final String displayName;
  final GroupRole role;
  final GroupMembershipState membership;
  final bool verified;
  final List<String> deviceIds;

  bool get isActive => membership == GroupMembershipState.active;

  GroupMember copyWith({
    String? displayName,
    GroupRole? role,
    GroupMembershipState? membership,
    bool? verified,
    Iterable<String>? deviceIds,
  }) => GroupMember(
    userId: userId,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    membership: membership ?? this.membership,
    verified: verified ?? this.verified,
    deviceIds: deviceIds ?? this.deviceIds,
  );

  List<Object?> get canonicalFields => [
    userId.toLowerCase(),
    displayName,
    role.index,
    membership.index,
    verified,
    deviceIds,
  ];

  @override
  bool operator ==(Object other) =>
      other is GroupMember &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.role == role &&
      other.membership == membership &&
      other.verified == verified &&
      _listEquals(other.deviceIds, deviceIds);

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    role,
    membership,
    verified,
    Object.hashAll(deviceIds),
  );
}

final class GroupState {
  GroupState({
    required this.groupId,
    required this.metadata,
    required this.invitationPolicy,
    required this.historySharingPolicy,
    required Iterable<GroupMember> members,
    required this.controlRevision,
    required this.controlStateHash,
    required this.acceptedEpoch,
    this.lifecycle = GroupLifecycle.active,
    this.quarantineReason,
  }) : members = List.unmodifiable(_sortedMembers(members)) {
    if (!_isHex(groupId, 32) ||
        controlRevision < 1 ||
        !_isHex(controlStateHash, 32) ||
        acceptedEpoch < 0 ||
        !metadata.isValid ||
        this.members.length > maximumMembers ||
        this.members
                .map((member) => member.userId.toLowerCase())
                .toSet()
                .length !=
            this.members.length) {
      throw const FormatException('invalid group state');
    }
    final activeOwners = this.members
        .where((member) => member.isActive && member.role == GroupRole.owner)
        .length;
    if (activeOwners != 1 && lifecycle != GroupLifecycle.left) {
      throw const FormatException('a live group requires exactly one owner');
    }
    if ((lifecycle == GroupLifecycle.forkQuarantined ||
            lifecycle == GroupLifecycle.controlQuarantined) !=
        (quarantineReason != null)) {
      throw const FormatException('quarantine state and reason mismatch');
    }
  }

  static const maximumMembers = 50;

  final String groupId;
  final GroupMetadata metadata;
  final GroupInvitationPolicy invitationPolicy;
  final GroupHistorySharingPolicy historySharingPolicy;
  final List<GroupMember> members;
  final int controlRevision;
  final String controlStateHash;
  final int acceptedEpoch;
  final GroupLifecycle lifecycle;
  final GroupQuarantineReason? quarantineReason;

  Iterable<GroupMember> get activeMembers =>
      members.where((member) => member.isActive);

  GroupMember? member(String userId) {
    final normalized = userId.toLowerCase();
    for (final member in members) {
      if (member.userId.toLowerCase() == normalized) return member;
    }
    return null;
  }

  GroupState copyWith({
    GroupMetadata? metadata,
    GroupInvitationPolicy? invitationPolicy,
    GroupHistorySharingPolicy? historySharingPolicy,
    Iterable<GroupMember>? members,
    int? controlRevision,
    String? controlStateHash,
    int? acceptedEpoch,
    GroupLifecycle? lifecycle,
    GroupQuarantineReason? quarantineReason,
    bool clearQuarantineReason = false,
  }) => GroupState(
    groupId: groupId,
    metadata: metadata ?? this.metadata,
    invitationPolicy: invitationPolicy ?? this.invitationPolicy,
    historySharingPolicy: historySharingPolicy ?? this.historySharingPolicy,
    members: members ?? this.members,
    controlRevision: controlRevision ?? this.controlRevision,
    controlStateHash: controlStateHash ?? this.controlStateHash,
    acceptedEpoch: acceptedEpoch ?? this.acceptedEpoch,
    lifecycle: lifecycle ?? this.lifecycle,
    quarantineReason: clearQuarantineReason
        ? null
        : quarantineReason ?? this.quarantineReason,
  );
}

abstract final class GroupAuthorization {
  static Set<GroupPermission> permissionsFor(
    GroupState state,
    String actorUserId,
  ) {
    final member = state.member(actorUserId);
    if (member == null) return const {};
    if (!member.isActive) {
      return const {GroupPermission.viewHistory};
    }
    if (state.lifecycle != GroupLifecycle.active) {
      return const {GroupPermission.viewHistory};
    }

    final permissions = <GroupPermission>{
      GroupPermission.viewHistory,
      GroupPermission.sendMessages,
      GroupPermission.leave,
    };
    if (_mayInvite(state.invitationPolicy, member.role)) {
      permissions.add(GroupPermission.inviteMembers);
    }
    if (member.role == GroupRole.admin || member.role == GroupRole.owner) {
      permissions
        ..add(GroupPermission.removeMembers)
        ..add(GroupPermission.editMetadata)
        ..add(GroupPermission.pinMessages);
    }
    if (member.role == GroupRole.owner) {
      permissions
        ..add(GroupPermission.editInvitationPolicy)
        ..add(GroupPermission.editHistorySharingPolicy)
        ..add(GroupPermission.changeRoles)
        ..add(GroupPermission.transferOwnership);
    }
    return UnmodifiableSetView(permissions);
  }

  static bool allows(
    GroupState state,
    String actorUserId,
    GroupPermission permission,
  ) => permissionsFor(state, actorUserId).contains(permission);

  static bool canRemove(
    GroupState state, {
    required String actorUserId,
    required String targetUserId,
  }) {
    if (actorUserId.toLowerCase() == targetUserId.toLowerCase() ||
        !allows(state, actorUserId, GroupPermission.removeMembers)) {
      return false;
    }
    final actor = state.member(actorUserId);
    final target = state.member(targetUserId);
    if (actor == null || target == null || !target.isActive) return false;
    if (target.role == GroupRole.owner) return false;
    return actor.role == GroupRole.owner || target.role == GroupRole.member;
  }

  static bool canChangeRole(
    GroupState state, {
    required String actorUserId,
    required String targetUserId,
    required GroupRole role,
  }) {
    if (role == GroupRole.owner ||
        actorUserId.toLowerCase() == targetUserId.toLowerCase() ||
        !allows(state, actorUserId, GroupPermission.changeRoles)) {
      return false;
    }
    final target = state.member(targetUserId);
    return target != null && target.isActive && target.role != GroupRole.owner;
  }

  static bool canLeave(GroupState state, String actorUserId) {
    if (!allows(state, actorUserId, GroupPermission.leave)) return false;
    final actor = state.member(actorUserId)!;
    return actor.role != GroupRole.owner || state.activeMembers.length == 1;
  }

  static bool _mayInvite(GroupInvitationPolicy policy, GroupRole role) =>
      switch (policy) {
        GroupInvitationPolicy.ownerOnly => role == GroupRole.owner,
        GroupInvitationPolicy.ownerAndAdmins => role != GroupRole.member,
        GroupInvitationPolicy.allMembers => true,
      };
}

sealed class GroupControlOperation {
  const GroupControlOperation();

  int get code;
  bool get changesMembership;
  GroupPermission? get requiredPermission;
  List<Object?> get canonicalFields;
}

final class CreateGroupOperation extends GroupControlOperation {
  CreateGroupOperation({
    required this.metadata,
    required this.invitationPolicy,
    required this.historySharingPolicy,
    required Iterable<GroupMember> initialMembers,
  }) : initialMembers = List.unmodifiable(_sortedMembers(initialMembers));

  final GroupMetadata metadata;
  final GroupInvitationPolicy invitationPolicy;
  final GroupHistorySharingPolicy historySharingPolicy;
  final List<GroupMember> initialMembers;

  @override
  int get code => 1;
  @override
  bool get changesMembership => true;
  @override
  GroupPermission? get requiredPermission => null;
  @override
  List<Object?> get canonicalFields => [
    code,
    metadata.name,
    metadata.description,
    metadata.photoCapability,
    invitationPolicy.index,
    historySharingPolicy.index,
    [for (final member in initialMembers) member.canonicalFields],
  ];
}

final class UpdateGroupMetadataOperation extends GroupControlOperation {
  const UpdateGroupMetadataOperation(this.metadata);

  final GroupMetadata metadata;
  @override
  int get code => 2;
  @override
  bool get changesMembership => false;
  @override
  GroupPermission get requiredPermission => GroupPermission.editMetadata;
  @override
  List<Object?> get canonicalFields => [
    code,
    metadata.name,
    metadata.description,
    metadata.photoCapability,
  ];
}

final class UpdateGroupPoliciesOperation extends GroupControlOperation {
  const UpdateGroupPoliciesOperation({
    required this.invitationPolicy,
    required this.historySharingPolicy,
  });

  final GroupInvitationPolicy invitationPolicy;
  final GroupHistorySharingPolicy historySharingPolicy;
  @override
  int get code => 3;
  @override
  bool get changesMembership => false;
  @override
  GroupPermission get requiredPermission =>
      GroupPermission.editInvitationPolicy;
  @override
  List<Object?> get canonicalFields => [
    code,
    invitationPolicy.index,
    historySharingPolicy.index,
  ];
}

final class InviteGroupMembersOperation extends GroupControlOperation {
  InviteGroupMembersOperation(Iterable<GroupMember> members)
    : members = List.unmodifiable(_sortedMembers(members));

  final List<GroupMember> members;
  @override
  int get code => 4;
  @override
  bool get changesMembership => true;
  @override
  GroupPermission get requiredPermission => GroupPermission.inviteMembers;
  @override
  List<Object?> get canonicalFields => [
    code,
    [for (final member in members) member.canonicalFields],
  ];
}

final class RemoveGroupMemberOperation extends GroupControlOperation {
  const RemoveGroupMemberOperation(this.targetUserId);

  final String targetUserId;
  @override
  int get code => 5;
  @override
  bool get changesMembership => true;
  @override
  GroupPermission get requiredPermission => GroupPermission.removeMembers;
  @override
  List<Object?> get canonicalFields => [code, targetUserId.toLowerCase()];
}

final class LeaveGroupOperation extends GroupControlOperation {
  const LeaveGroupOperation();

  @override
  int get code => 6;
  @override
  bool get changesMembership => true;
  @override
  GroupPermission get requiredPermission => GroupPermission.leave;
  @override
  List<Object?> get canonicalFields => [code];
}

final class ChangeGroupRoleOperation extends GroupControlOperation {
  const ChangeGroupRoleOperation({
    required this.targetUserId,
    required this.role,
  });

  final String targetUserId;
  final GroupRole role;
  @override
  int get code => 7;
  @override
  bool get changesMembership => false;
  @override
  GroupPermission get requiredPermission => GroupPermission.changeRoles;
  @override
  List<Object?> get canonicalFields => [
    code,
    targetUserId.toLowerCase(),
    role.index,
  ];
}

final class TransferGroupOwnershipOperation extends GroupControlOperation {
  const TransferGroupOwnershipOperation(this.targetUserId);

  final String targetUserId;
  @override
  int get code => 8;
  @override
  bool get changesMembership => false;
  @override
  GroupPermission get requiredPermission => GroupPermission.transferOwnership;
  @override
  List<Object?> get canonicalFields => [code, targetUserId.toLowerCase()];
}

final class GroupControlEvent {
  GroupControlEvent({
    this.protocolVersion = 1,
    required this.eventId,
    required this.groupId,
    required this.revision,
    required this.previousControlStateHash,
    required this.mlsEpoch,
    required this.mlsCommitHash,
    required this.signerUserId,
    required this.signerDeviceId,
    required this.createdMs,
    required this.operation,
  }) {
    if (protocolVersion != 1 ||
        !_isHex(eventId, 16) ||
        !_isHex(groupId, 32) ||
        revision < 1 ||
        (previousControlStateHash != null &&
            !_isHex(previousControlStateHash!, 32)) ||
        mlsEpoch < 0 ||
        (mlsCommitHash != null && !_isHex(mlsCommitHash!, 32)) ||
        createdMs < 0 ||
        (operation.changesMembership && mlsCommitHash == null) ||
        (!operation.changesMembership && mlsCommitHash != null)) {
      throw const FormatException('invalid group control event');
    }
  }

  final int protocolVersion;
  final String eventId;
  final String groupId;
  final int revision;
  final String? previousControlStateHash;
  final int mlsEpoch;
  final String? mlsCommitHash;
  final String signerUserId;
  final String signerDeviceId;
  final int createdMs;
  final GroupControlOperation operation;

  /// A fixed-order projection consumed by the real crypto-core port in piece 19.
  ///
  /// It deliberately is not a Dart wire encoder. Production deterministic-CBOR and
  /// signatures remain owned by the reviewed shared Rust core.
  List<Object?> get canonicalFields => [
    protocolVersion,
    eventId,
    groupId,
    revision,
    previousControlStateHash,
    mlsEpoch,
    mlsCommitHash,
    signerUserId.toLowerCase(),
    signerDeviceId.toLowerCase(),
    createdMs,
    operation.canonicalFields,
  ];

  String get deterministicProjection => jsonEncode(canonicalFields);
}

final class SignedGroupControlEvent {
  SignedGroupControlEvent({
    required this.event,
    required this.controlStateHash,
    required Uint8List canonicalBytes,
    required Uint8List signature,
  }) : canonicalBytes = Uint8List.fromList(canonicalBytes),
       signature = Uint8List.fromList(signature) {
    if (!_isHex(controlStateHash, 32) ||
        this.canonicalBytes.isEmpty ||
        this.signature.isEmpty) {
      throw const FormatException('invalid signed group control');
    }
  }

  final GroupControlEvent event;
  final String controlStateHash;
  final Uint8List canonicalBytes;
  final Uint8List signature;
}

sealed class GroupControlApplyResult {
  const GroupControlApplyResult();
}

final class GroupControlAccepted extends GroupControlApplyResult {
  const GroupControlAccepted(this.state);
  final GroupState state;
}

final class GroupControlDuplicate extends GroupControlApplyResult {
  const GroupControlDuplicate(this.state);
  final GroupState state;
}

final class GroupControlQuarantined extends GroupControlApplyResult {
  const GroupControlQuarantined(this.state, this.reason);
  final GroupState? state;
  final GroupQuarantineReason reason;
}

final class GroupControlStateMachine {
  const GroupControlStateMachine();

  GroupControlApplyResult apply({
    required GroupState? previous,
    required SignedGroupControlEvent signedControl,
    required String localUserId,
  }) {
    final event = signedControl.event;
    if (previous == null) {
      return _create(event, signedControl.controlStateHash, localUserId);
    }
    if (event.groupId != previous.groupId) {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.brokenControlChain,
      );
    }
    if (event.revision == previous.controlRevision &&
        signedControl.controlStateHash == previous.controlStateHash) {
      return GroupControlDuplicate(previous);
    }
    if (event.revision <= previous.controlRevision) {
      return GroupControlQuarantined(
        previous,
        event.revision == previous.controlRevision
            ? GroupQuarantineReason.siblingCommit
            : GroupQuarantineReason.staleRevision,
      );
    }
    if (event.revision != previous.controlRevision + 1 ||
        event.previousControlStateHash != previous.controlStateHash) {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.brokenControlChain,
      );
    }
    final expectedEpoch =
        previous.acceptedEpoch + (event.operation.changesMembership ? 1 : 0);
    if (event.mlsEpoch != expectedEpoch) {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.invalidMembership,
      );
    }
    final actor = previous.member(event.signerUserId);
    final permission = event.operation.requiredPermission;
    if (actor == null ||
        !actor.isActive ||
        permission == null ||
        !GroupAuthorization.allows(previous, event.signerUserId, permission)) {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.unauthorizedControl,
      );
    }

    final next = _applyOperation(previous, event, localUserId);
    if (next == null) {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.unauthorizedControl,
      );
    }
    try {
      return GroupControlAccepted(
        GroupState(
          groupId: previous.groupId,
          metadata: next.metadata,
          invitationPolicy: next.invitationPolicy,
          historySharingPolicy: next.historySharingPolicy,
          members: next.members,
          controlRevision: event.revision,
          controlStateHash: signedControl.controlStateHash,
          acceptedEpoch: event.mlsEpoch,
          lifecycle: next.lifecycle,
        ),
      );
    } on FormatException {
      return GroupControlQuarantined(
        previous,
        GroupQuarantineReason.invalidMembership,
      );
    }
  }

  GroupControlApplyResult _create(
    GroupControlEvent event,
    String controlStateHash,
    String localUserId,
  ) {
    final operation = event.operation;
    if (operation is! CreateGroupOperation ||
        event.revision != 1 ||
        event.previousControlStateHash != null ||
        event.mlsEpoch != 0 ||
        !operation.metadata.isValid ||
        operation.initialMembers.isEmpty ||
        operation.initialMembers.length > GroupState.maximumMembers) {
      return const GroupControlQuarantined(
        null,
        GroupQuarantineReason.invalidMembership,
      );
    }
    final owner = operation.initialMembers
        .where((member) => member.isActive && member.role == GroupRole.owner)
        .toList(growable: false);
    if (owner.length != 1 ||
        owner.single.userId.toLowerCase() != event.signerUserId.toLowerCase()) {
      return const GroupControlQuarantined(
        null,
        GroupQuarantineReason.unauthorizedControl,
      );
    }
    try {
      return GroupControlAccepted(
        GroupState(
          groupId: event.groupId,
          metadata: operation.metadata.normalized(),
          invitationPolicy: operation.invitationPolicy,
          historySharingPolicy: operation.historySharingPolicy,
          members: operation.initialMembers,
          controlRevision: 1,
          controlStateHash: controlStateHash,
          acceptedEpoch: 0,
          lifecycle:
              operation.initialMembers.any(
                (member) =>
                    member.userId.toLowerCase() == localUserId.toLowerCase() &&
                    member.isActive,
              )
              ? GroupLifecycle.active
              : GroupLifecycle.removed,
        ),
      );
    } on FormatException {
      return const GroupControlQuarantined(
        null,
        GroupQuarantineReason.invalidMembership,
      );
    }
  }

  _MutableGroupState? _applyOperation(
    GroupState previous,
    GroupControlEvent event,
    String localUserId,
  ) {
    final mutable = _MutableGroupState.from(previous);
    final actorId = event.signerUserId.toLowerCase();
    switch (event.operation) {
      case CreateGroupOperation():
        return null;
      case UpdateGroupMetadataOperation(:final metadata):
        if (!metadata.isValid) return null;
        mutable.metadata = metadata.normalized();
      case UpdateGroupPoliciesOperation(
        :final invitationPolicy,
        :final historySharingPolicy,
      ):
        if (!GroupAuthorization.allows(
          previous,
          actorId,
          GroupPermission.editHistorySharingPolicy,
        )) {
          return null;
        }
        mutable
          ..invitationPolicy = invitationPolicy
          ..historySharingPolicy = historySharingPolicy;
      case InviteGroupMembersOperation(:final members):
        if (members.isEmpty ||
            members.any(
              (member) => !member.isActive || member.role != GroupRole.member,
            ) ||
            previous.activeMembers.length + members.length >
                GroupState.maximumMembers) {
          return null;
        }
        final ids = mutable.members
            .map((member) => member.userId.toLowerCase())
            .toSet();
        for (final member in members) {
          if (!ids.add(member.userId.toLowerCase())) return null;
          mutable.members.add(member);
        }
      case RemoveGroupMemberOperation(:final targetUserId):
        if (!GroupAuthorization.canRemove(
          previous,
          actorUserId: actorId,
          targetUserId: targetUserId,
        )) {
          return null;
        }
        mutable.replaceMember(
          targetUserId,
          (member) => member.copyWith(membership: GroupMembershipState.removed),
        );
        if (targetUserId.toLowerCase() == localUserId.toLowerCase()) {
          mutable.lifecycle = GroupLifecycle.removed;
        }
      case LeaveGroupOperation():
        if (!GroupAuthorization.canLeave(previous, actorId)) return null;
        mutable.replaceMember(
          actorId,
          (member) => member.copyWith(membership: GroupMembershipState.left),
        );
        if (actorId == localUserId.toLowerCase()) {
          mutable.lifecycle = GroupLifecycle.left;
        }
      case ChangeGroupRoleOperation(:final targetUserId, :final role):
        if (!GroupAuthorization.canChangeRole(
          previous,
          actorUserId: actorId,
          targetUserId: targetUserId,
          role: role,
        )) {
          return null;
        }
        mutable.replaceMember(
          targetUserId,
          (member) => member.copyWith(role: role),
        );
      case TransferGroupOwnershipOperation(:final targetUserId):
        final target = previous.member(targetUserId);
        if (target == null ||
            !target.isActive ||
            target.role == GroupRole.owner ||
            !GroupAuthorization.allows(
              previous,
              actorId,
              GroupPermission.transferOwnership,
            )) {
          return null;
        }
        mutable
          ..replaceMember(
            actorId,
            (member) => member.copyWith(role: GroupRole.admin),
          )
          ..replaceMember(
            targetUserId,
            (member) => member.copyWith(role: GroupRole.owner),
          );
    }
    return mutable;
  }
}

final class GroupCreationIntent {
  GroupCreationIntent({
    required this.creatorUserId,
    required this.creatorDeviceId,
    required this.metadata,
    required Iterable<GroupMember> members,
    this.invitationPolicy = GroupInvitationPolicy.ownerAndAdmins,
    this.historySharingPolicy = GroupHistorySharingPolicy.reshareAvailable,
    required this.createdMs,
  }) : members = List.unmodifiable(_sortedMembers(members));

  final String creatorUserId;
  final String creatorDeviceId;
  final GroupMetadata metadata;
  final List<GroupMember> members;
  final GroupInvitationPolicy invitationPolicy;
  final GroupHistorySharingPolicy historySharingPolicy;
  final int createdMs;
}

final class PreparedGroupTransition {
  PreparedGroupTransition({
    required this.signedControl,
    required Uint8List newOpaqueMlsState,
    required Uint8List mlsObject,
    required this.mutationId,
    this.outbound = true,
  }) : newOpaqueMlsState = Uint8List.fromList(newOpaqueMlsState),
       mlsObject = Uint8List.fromList(mlsObject) {
    if (this.newOpaqueMlsState.isEmpty ||
        this.mlsObject.isEmpty ||
        mutationId.isEmpty) {
      throw const FormatException('invalid prepared group transition');
    }
  }

  final SignedGroupControlEvent signedControl;
  final Uint8List newOpaqueMlsState;
  final Uint8List mlsObject;
  final String mutationId;
  final bool outbound;
}

final class PreparedGroupMessage {
  PreparedGroupMessage({
    required this.groupId,
    required this.messageId,
    required this.senderUserId,
    required this.senderDeviceId,
    required this.text,
    required this.createdMs,
    required this.epoch,
    required Uint8List newOpaqueMlsState,
    required Uint8List mlsObject,
    required this.operationId,
  }) : newOpaqueMlsState = Uint8List.fromList(newOpaqueMlsState),
       mlsObject = Uint8List.fromList(mlsObject);

  final String groupId;
  final String messageId;
  final String senderUserId;
  final String senderDeviceId;
  final String text;
  final int createdMs;
  final int epoch;
  final Uint8List newOpaqueMlsState;
  final Uint8List mlsObject;
  final String operationId;
}

final class GroupMessage {
  const GroupMessage({
    required this.messageId,
    required this.groupId,
    required this.senderUserId,
    required this.text,
    required this.createdMs,
    required this.localPreviewOnly,
  });

  final String messageId;
  final String groupId;
  final String senderUserId;
  final String text;
  final int createdMs;
  final bool localPreviewOnly;
}

final class GroupQuarantineRecord {
  GroupQuarantineRecord({
    required this.groupId,
    required this.reason,
    required Uint8List opaqueDigest,
    required this.receivedAt,
  }) : opaqueDigest = Uint8List.fromList(opaqueDigest);

  final String groupId;
  final GroupQuarantineReason reason;
  final Uint8List opaqueDigest;
  final DateTime receivedAt;
}

final class _MutableGroupState {
  _MutableGroupState({
    required this.metadata,
    required this.invitationPolicy,
    required this.historySharingPolicy,
    required this.members,
    required this.lifecycle,
  });

  factory _MutableGroupState.from(GroupState state) => _MutableGroupState(
    metadata: state.metadata,
    invitationPolicy: state.invitationPolicy,
    historySharingPolicy: state.historySharingPolicy,
    members: state.members.toList(),
    lifecycle: state.lifecycle,
  );

  GroupMetadata metadata;
  GroupInvitationPolicy invitationPolicy;
  GroupHistorySharingPolicy historySharingPolicy;
  final List<GroupMember> members;
  GroupLifecycle lifecycle;

  void replaceMember(
    String userId,
    GroupMember Function(GroupMember member) replace,
  ) {
    final normalized = userId.toLowerCase();
    final index = members.indexWhere(
      (member) => member.userId.toLowerCase() == normalized,
    );
    if (index < 0) throw const FormatException('missing member');
    members[index] = replace(members[index]);
  }
}

List<GroupMember> _sortedMembers(Iterable<GroupMember> values) {
  final result = values.toList(growable: false)
    ..sort(
      (left, right) =>
          left.userId.toLowerCase().compareTo(right.userId.toLowerCase()),
    );
  return result;
}

List<String> _sortedUnique(Iterable<String> values) {
  final result = values.map((value) => value.toLowerCase()).toSet().toList()
    ..sort();
  return result;
}

bool _isHex(String value, int byteLength) =>
    value.length == byteLength * 2 && RegExp(r'^[0-9a-f]+$').hasMatch(value);

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
