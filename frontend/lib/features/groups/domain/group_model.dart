import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/group_sync_model.dart';

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

    return _activeMemberPermissions(state, member);
  }

  static Set<GroupPermission> _activeMemberPermissions(
    GroupState state,
    GroupMember member,
  ) {
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

  /// Evaluates a signed control actor against the historical global roster.
  /// Local lifecycle is intentionally irrelevant during transcript replay.
  static bool allowsControl(
    GroupState state,
    String actorUserId,
    GroupPermission permission,
  ) {
    final member = state.member(actorUserId);
    return member != null &&
        member.isActive &&
        _activeMemberPermissions(state, member).contains(permission);
  }

  static bool canRemove(
    GroupState state, {
    required String actorUserId,
    required String targetUserId,
    bool forControl = false,
  }) {
    if (actorUserId.toLowerCase() == targetUserId.toLowerCase() ||
        !(forControl ? allowsControl : allows)(
          state,
          actorUserId,
          GroupPermission.removeMembers,
        )) {
      return false;
    }
    final actor = state.member(actorUserId);
    final target = state.member(targetUserId);
    if (actor == null || target == null || !isEvictable(target)) return false;
    if (target.role == GroupRole.owner) return false;
    return actor.role == GroupRole.owner || target.role == GroupRole.member;
  }

  static bool canChangeRole(
    GroupState state, {
    required String actorUserId,
    required String targetUserId,
    required GroupRole role,
    bool forControl = false,
  }) {
    if (role == GroupRole.owner ||
        actorUserId.toLowerCase() == targetUserId.toLowerCase() ||
        !(forControl ? allowsControl : allows)(
          state,
          actorUserId,
          GroupPermission.changeRoles,
        )) {
      return false;
    }
    final target = state.member(targetUserId);
    return target != null && target.isActive && target.role != GroupRole.owner;
  }

  /// A member who announced a leave is still in the MLS tree and still holds
  /// the current epoch secret until a remaining member commits its `Remove`.
  /// Eviction must therefore stay authorized for [GroupMembershipState.left],
  /// while an already-evicted member is not a valid target again.
  static bool isEvictable(GroupMember member) =>
      member.membership != GroupMembershipState.removed;

  static bool canLeave(
    GroupState state,
    String actorUserId, {
    bool forControl = false,
  }) {
    if (!(forControl ? allowsControl : allows)(
      state,
      actorUserId,
      GroupPermission.leave,
    )) {
      return false;
    }
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

  /// A leave carries no Commit of its own.
  ///
  /// RFC 9420 section 12.4 forbids a Commit that removes its own committer, so
  /// a departing member cannot evict itself. The leave is an authenticated
  /// announcement at the current epoch that moves the member to
  /// [GroupMembershipState.left]; a remaining member then commits the `Remove`
  /// that evicts the leaf and moves it to [GroupMembershipState.removed].
  @override
  bool get changesMembership => false;
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

  factory GroupControlEvent.fromDeterministicProjection(String projection) {
    final fields = _projectionList(jsonDecode(projection), 11);
    return GroupControlEvent(
      protocolVersion: _projectionInteger(fields[0]),
      eventId: _projectionString(fields[1]),
      groupId: _projectionString(fields[2]),
      revision: _projectionInteger(fields[3]),
      previousControlStateHash: _projectionOptionalString(fields[4]),
      mlsEpoch: _projectionInteger(fields[5]),
      mlsCommitHash: _projectionOptionalString(fields[6]),
      signerUserId: _projectionString(fields[7]),
      signerDeviceId: _projectionString(fields[8]),
      createdMs: _projectionInteger(fields[9]),
      operation: _projectionOperation(fields[10]),
    );
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

final class GroupControlTranscriptEntry {
  GroupControlTranscriptEntry({
    required this.signedControl,
    required Uint8List signedPayload,
    required Uint8List signerAuthenticationProof,
  }) : signedPayload = Uint8List.fromList(signedPayload),
       signerAuthenticationProof = Uint8List.fromList(
         signerAuthenticationProof,
       ) {
    if (this.signedPayload.length < 8 ||
        this.signedPayload.length > 64 * 1024 ||
        this.signerAuthenticationProof.length < 8 ||
        this.signerAuthenticationProof.length > 16 * 1024) {
      throw const FormatException('invalid group control transcript entry');
    }
  }

  final SignedGroupControlEvent signedControl;
  final Uint8List signedPayload;
  final Uint8List signerAuthenticationProof;
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
        !GroupAuthorization.allowsControl(
          previous,
          event.signerUserId,
          permission,
        )) {
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
        event.mlsEpoch != 1 ||
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
          acceptedEpoch: 1,
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
        if (!GroupAuthorization.allowsControl(
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
        if (members.any(
          (member) => member.userId.toLowerCase() == localUserId.toLowerCase(),
        )) {
          mutable.lifecycle = GroupLifecycle.active;
        }
      case RemoveGroupMemberOperation(:final targetUserId):
        if (!GroupAuthorization.canRemove(
          previous,
          actorUserId: actorId,
          targetUserId: targetUserId,
          forControl: true,
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
        if (!GroupAuthorization.canLeave(previous, actorId, forControl: true)) {
          return null;
        }
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
          forControl: true,
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
            !GroupAuthorization.allowsControl(
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
    required Iterable<String> recipientUserIds,
    this.outbound = true,
    this.consumedKeyPackageState,
    this.controlTranscriptEntry,
    Iterable<GroupControlTranscriptEntry> precedingControlTranscript = const [],
  }) : newOpaqueMlsState = Uint8List.fromList(newOpaqueMlsState),
       mlsObject = Uint8List.fromList(mlsObject),
       precedingControlTranscript = List.unmodifiable(
         precedingControlTranscript,
       ),
       recipientUserIds = List.unmodifiable(
         recipientUserIds.map((value) => value.toLowerCase()).toSet(),
       ) {
    if (this.newOpaqueMlsState.isEmpty ||
        this.mlsObject.isEmpty ||
        mutationId.isEmpty ||
        this.precedingControlTranscript.length > 512 ||
        (this.precedingControlTranscript.isNotEmpty && outbound) ||
        (controlTranscriptEntry != null &&
            !_sameSignedControl(
              controlTranscriptEntry!.signedControl,
              signedControl,
            )) ||
        (consumedKeyPackageState != null &&
            (outbound || !signedControl.event.operation.changesMembership)) ||
        (outbound && this.recipientUserIds.isEmpty)) {
      throw const FormatException('invalid prepared group transition');
    }
  }

  final SignedGroupControlEvent signedControl;
  final Uint8List newOpaqueMlsState;
  final Uint8List mlsObject;
  final String mutationId;
  final List<String> recipientUserIds;
  final bool outbound;
  final ConsumedGroupKeyPackageState? consumedKeyPackageState;
  final GroupControlTranscriptEntry? controlTranscriptEntry;
  final List<GroupControlTranscriptEntry> precedingControlTranscript;
}

final class ConsumedGroupKeyPackageState {
  ConsumedGroupKeyPackageState({
    required this.deviceId,
    required this.expectedStateRevision,
    required Uint8List nextSealedState,
  }) : nextSealedState = Uint8List.fromList(nextSealedState) {
    if (!_groupUuid.hasMatch(deviceId) ||
        deviceId != deviceId.toLowerCase() ||
        expectedStateRevision <= 0 ||
        this.nextSealedState.isEmpty ||
        this.nextSealedState.length > 1024 * 1024) {
      throw const FormatException('invalid consumed KeyPackage state');
    }
  }

  final String deviceId;
  final int expectedStateRevision;
  final Uint8List nextSealedState;
}

final RegExp _groupUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

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
    required Iterable<String> recipientUserIds,
    this.outbound = true,
  }) : newOpaqueMlsState = Uint8List.fromList(newOpaqueMlsState),
       mlsObject = Uint8List.fromList(mlsObject),
       recipientUserIds = List.unmodifiable(
         recipientUserIds.map((value) => value.toLowerCase()).toSet(),
       ) {
    if ((outbound && this.recipientUserIds.isEmpty) ||
        (!outbound && this.recipientUserIds.isNotEmpty)) {
      throw const FormatException('group message requires recipients');
    }
  }

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
  final List<String> recipientUserIds;
  final bool outbound;
}

enum GroupMlsTransportKind { welcome, control, application }

final class GroupMlsTransportProbe {
  GroupMlsTransportProbe({
    required this.kind,
    required this.groupId,
    this.joinCapable = false,
  }) {
    if (!_isHex(groupId, 32)) {
      throw const FormatException('invalid group transport probe');
    }
  }

  final GroupMlsTransportKind kind;
  final String groupId;
  final bool joinCapable;
}

sealed class PreparedGroupInboxCommit implements GroupSyncReceiveCommit {
  const PreparedGroupInboxCommit();

  @override
  String get opaqueEventId;
  @override
  String get senderUserId;
  @override
  String get senderDeviceId;
}

final class PreparedGroupInboxTransition extends PreparedGroupInboxCommit {
  const PreparedGroupInboxTransition({
    required this.expectedPrevious,
    required this.next,
    required this.prepared,
  });

  final GroupState? expectedPrevious;
  final GroupState next;
  final PreparedGroupTransition prepared;

  @override
  String get opaqueEventId =>
      'group-control:${prepared.signedControl.event.eventId}';
  @override
  String get senderUserId => prepared.signedControl.event.signerUserId;
  @override
  String get senderDeviceId => prepared.signedControl.event.signerDeviceId;
}

/// A same-revision sibling control was authenticated and ordered.
///
/// When the local branch is canonical the sibling is recorded and dropped and
/// the group keeps running. When it is superseded the group is fork-quarantined
/// and waits for remove/re-add, because an applied MLS commit cannot be rewound.
final class PreparedGroupInboxForkResolution extends PreparedGroupInboxCommit {
  const PreparedGroupInboxForkResolution({
    required this.resolution,
    required this.record,
    required this.siblingEventId,
    required this.siblingSignerUserId,
    required this.siblingSignerDeviceId,
  });

  final GroupForkResolution resolution;
  final GroupQuarantineRecord record;
  final String siblingEventId;
  final String siblingSignerUserId;
  final String siblingSignerDeviceId;

  bool get localBranchRetained => resolution is GroupForkLocalBranchCanonical;

  @override
  String get opaqueEventId => 'group-fork:$siblingEventId';
  @override
  String get senderUserId => siblingSignerUserId;
  @override
  String get senderDeviceId => siblingSignerDeviceId;
}

final class PreparedGroupInboxMessage extends PreparedGroupInboxCommit {
  const PreparedGroupInboxMessage({
    required this.expectedGroup,
    required this.prepared,
  });

  final GroupState expectedGroup;
  final PreparedGroupMessage prepared;

  @override
  String get opaqueEventId => 'group-application:${prepared.messageId}';
  @override
  String get senderUserId => prepared.senderUserId;
  @override
  String get senderDeviceId => prepared.senderDeviceId;
}

final class GroupOutboundWork {
  GroupOutboundWork({
    required this.operationId,
    required this.groupId,
    required this.eventId,
    required this.epoch,
    required Uint8List openedMlsPayload,
    required Iterable<String> recipientUserIds,
  }) : openedMlsPayload = Uint8List.fromList(openedMlsPayload),
       recipientUserIds = List.unmodifiable(recipientUserIds) {
    if (operationId.isEmpty ||
        groupId.isEmpty ||
        eventId.isEmpty ||
        epoch < 0 ||
        this.openedMlsPayload.isEmpty ||
        this.recipientUserIds.isEmpty ||
        this.recipientUserIds.toSet().length != this.recipientUserIds.length) {
      throw const FormatException('invalid group outbound work');
    }
  }

  final String operationId;
  final String groupId;
  final String eventId;
  final int epoch;
  final Uint8List openedMlsPayload;
  final List<String> recipientUserIds;
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

/// Canonical ordering for two control branches accepted at the same revision.
///
/// The backend is an untrusted relay and group objects ride per-recipient
/// pairwise envelopes, so there is no delivery-service commit order to break the
/// tie. Both branches carry a control state hash over the full signed control
/// descriptor, so every honest device independently derives the same winner:
/// the lexicographically smallest hash. The rule is total, deterministic, and
/// needs no extra round trip.
abstract final class GroupForkCanonicalOrder {
  /// True when [candidateControlStateHash] outranks every hash in [rivals].
  ///
  /// Equal hashes mean the same control, which is not a fork.
  static bool outranks(
    String candidateControlStateHash,
    Iterable<String> rivals,
  ) {
    final candidate = candidateControlStateHash.toLowerCase();
    return rivals.every(
      (rival) => candidate.compareTo(rival.toLowerCase()) < 0,
    );
  }

  static String canonical(Iterable<String> controlStateHashes) {
    final sorted =
        controlStateHashes
            .map((value) => value.toLowerCase())
            .toList(growable: false)
          ..sort();
    if (sorted.isEmpty) {
      throw const FormatException('no control branch to order');
    }
    return sorted.first;
  }
}

/// Outcome of comparing the locally accepted control branch against sibling
/// controls another device accepted at the same revision.
///
/// An applied MLS commit cannot be rewound: the previous epoch secrets are gone
/// by construction. A superseded local branch is therefore recovered by
/// quarantine plus remove/re-add, never by rollback.
sealed class GroupForkResolution {
  const GroupForkResolution();
}

/// The local branch wins. Every sibling is stale and is dropped.
final class GroupForkLocalBranchCanonical extends GroupForkResolution {
  GroupForkLocalBranchCanonical({required Iterable<String> supersededEventIds})
    : supersededEventIds = List.unmodifiable(
        supersededEventIds.map((value) => value.toLowerCase()).toSet().toList()
          ..sort(),
      );

  final List<String> supersededEventIds;
}

/// A sibling branch wins. The local group must stop and be re-admitted.
final class GroupForkLocalBranchSuperseded extends GroupForkResolution {
  const GroupForkLocalBranchSuperseded({
    required this.canonicalEventId,
    required this.canonicalControlStateHash,
    required this.canonicalSignerUserId,
  });

  final String canonicalEventId;
  final String canonicalControlStateHash;
  final String canonicalSignerUserId;
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

bool _sameSignedControl(
  SignedGroupControlEvent left,
  SignedGroupControlEvent right,
) =>
    left.event.deterministicProjection == right.event.deterministicProjection &&
    left.controlStateHash == right.controlStateHash &&
    _byteListEquals(left.canonicalBytes, right.canonicalBytes) &&
    _byteListEquals(left.signature, right.signature);

bool _byteListEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

GroupControlOperation _projectionOperation(Object? value) {
  final fields = _projectionList(value);
  if (fields.isEmpty) throw const FormatException('missing group operation');
  return switch (_projectionInteger(fields[0])) {
    1 => CreateGroupOperation(
      metadata: _projectionMetadata(fields, 1),
      invitationPolicy: _projectionEnum(
        GroupInvitationPolicy.values,
        fields[4],
      ),
      historySharingPolicy: _projectionEnum(
        GroupHistorySharingPolicy.values,
        fields[5],
      ),
      initialMembers: _projectionMembers(fields[6]),
    ),
    2 => UpdateGroupMetadataOperation(_projectionMetadata(fields, 1)),
    3 => UpdateGroupPoliciesOperation(
      invitationPolicy: _projectionEnum(
        GroupInvitationPolicy.values,
        fields[1],
      ),
      historySharingPolicy: _projectionEnum(
        GroupHistorySharingPolicy.values,
        fields[2],
      ),
    ),
    4 => InviteGroupMembersOperation(_projectionMembers(fields[1])),
    5 => RemoveGroupMemberOperation(_projectionString(fields[1])),
    6 => const LeaveGroupOperation(),
    7 => ChangeGroupRoleOperation(
      targetUserId: _projectionString(fields[1]),
      role: _projectionEnum(GroupRole.values, fields[2]),
    ),
    8 => TransferGroupOwnershipOperation(_projectionString(fields[1])),
    _ => throw const FormatException('unsupported group operation'),
  };
}

GroupMetadata _projectionMetadata(List<Object?> fields, int offset) =>
    GroupMetadata(
      name: _projectionString(fields[offset]),
      description: _projectionString(fields[offset + 1]),
      photoCapability: _projectionOptionalString(fields[offset + 2]),
    );

List<GroupMember> _projectionMembers(Object? value) => [
  for (final member in _projectionList(value)) _projectionMember(member),
];

GroupMember _projectionMember(Object? value) {
  final fields = _projectionList(value, 6);
  return GroupMember(
    userId: _projectionString(fields[0]),
    displayName: _projectionString(fields[1]),
    role: _projectionEnum(GroupRole.values, fields[2]),
    membership: _projectionEnum(GroupMembershipState.values, fields[3]),
    verified: fields[4] is bool
        ? fields[4]! as bool
        : throw const FormatException('invalid verified member flag'),
    deviceIds: [
      for (final deviceId in _projectionList(fields[5]))
        _projectionString(deviceId),
    ],
  );
}

List<Object?> _projectionList(Object? value, [int? exactLength]) {
  if (value is! List<Object?> ||
      (exactLength != null && value.length != exactLength)) {
    throw const FormatException('invalid group control projection');
  }
  return value;
}

int _projectionInteger(Object? value) {
  if (value is! int) throw const FormatException('invalid integer');
  return value;
}

String _projectionString(Object? value) {
  if (value is! String) throw const FormatException('invalid string');
  return value;
}

String? _projectionOptionalString(Object? value) =>
    value == null ? null : _projectionString(value);

T _projectionEnum<T>(List<T> values, Object? value) {
  final index = _projectionInteger(value);
  if (index < 0 || index >= values.length) {
    throw const FormatException('invalid enum');
  }
  return values[index];
}
