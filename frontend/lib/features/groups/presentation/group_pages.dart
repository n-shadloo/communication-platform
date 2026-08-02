import 'dart:async';

import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/group_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/messaging/presentation/chat_timeline.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef CreateGroupCallback =
    Future<Result<GroupState>> Function(
      GroupMetadata metadata,
      List<GroupMember> selectedMembers,
    );
typedef MutateGroupCallback =
    Future<Result<GroupState>> Function(GroupControlOperation operation);
typedef SendGroupMessageCallback =
    Future<Result<GroupMessage>> Function(String text);

final class GroupPickerContact {
  const GroupPickerContact({
    required this.userId,
    required this.name,
    required this.verified,
  });

  factory GroupPickerContact.fromContact(ContactProjection contact) =>
      GroupPickerContact(
        userId: contact.userId,
        name: contact.presentationName,
        verified: contact.trustState == ContactTrustState.verified,
      );

  final String userId;
  final String name;
  final bool verified;
}

class CreateGroupPage extends ConsumerWidget {
  const CreateGroupPage({
    this.injectedContacts,
    this.currentUserId,
    this.currentDeviceId,
    this.ownerDisplayName,
    this.onCreate,
    super.key,
  });

  final List<GroupPickerContact>? injectedContacts;
  final String? currentUserId;
  final String? currentDeviceId;
  final String? ownerDisplayName;
  final CreateGroupCallback? onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (injectedContacts != null && onCreate != null) {
      return _CreateGroupFlow(contacts: injectedContacts!, onCreate: onCreate!);
    }
    if (ref.watch(groupFeatureAvailabilityProvider) !=
        GroupFeatureAvailability.developmentPreview) {
      return const GroupProductionGatePage();
    }
    final auth = ref.watch(authenticationControllerProvider);
    final userId = currentUserId ?? auth.userId;
    if (userId == null) {
      return const GroupProductionGatePage();
    }
    final contacts = ref.watch(contactListProvider(userId));
    final device = ref.watch(currentMessagingDeviceIdProvider);
    final useCases = ref.watch(groupUseCasesProvider);
    return contacts.when(
      loading: () => _loadingPage(context),
      error: (_, _) => _errorPage(context),
      data: (values) => device.when(
        loading: () => _loadingPage(context),
        error: (_, _) => _errorPage(context),
        data: (resolvedDevice) => useCases.when(
          loading: () => _loadingPage(context),
          error: (_, _) => _errorPage(context),
          data: (resolvedUseCases) => _CreateGroupFlow(
            contacts: values
                .map(GroupPickerContact.fromContact)
                .toList(growable: false),
            onCreate: (metadata, selected) => resolvedUseCases.create(
              currentUserId: userId,
              currentDeviceId: currentDeviceId ?? resolvedDevice,
              ownerDisplayName: ownerDisplayName ?? auth.username ?? userId,
              metadata: metadata,
              selectedMembers: selected,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateGroupFlow extends StatefulWidget {
  const _CreateGroupFlow({required this.contacts, required this.onCreate});

  final List<GroupPickerContact> contacts;
  final CreateGroupCallback onCreate;

  @override
  State<_CreateGroupFlow> createState() => _CreateGroupFlowState();
}

class _CreateGroupFlowState extends State<_CreateGroupFlow> {
  final _selected = <String>{};
  final _name = TextEditingController();
  final _description = TextEditingController();
  var _details = false;
  var _photoSelected = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('create-group-screen'),
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: strings.authBackAction,
          onPressed: () {
            if (_details) {
              setState(() {
                _details = false;
                _error = null;
              });
            } else if (context.canPop()) {
              context.pop();
            } else {
              context.go('/chats/new');
            }
          },
          kind: AppButtonKind.ghost,
        ),
        title: Text(strings.groupCreateTitle),
      ),
      body: _ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.x4),
          children: [
            const _DevelopmentPreviewBanner(),
            const SizedBox(height: AppSpacing.x4),
            Text(
              _details
                  ? strings.groupDetailsTitle
                  : strings.groupPickMembersTitle,
              style: context.tokens.typography.section,
            ),
            const SizedBox(height: AppSpacing.x4),
            if (_details) ...[
              AppField(
                key: const ValueKey('group-name-field'),
                label: strings.groupNameLabel,
                controller: _name,
                maxLength: GroupMetadata.maximumNameScalars,
                enabled: !_busy,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: AppSpacing.x4),
              AppField(
                key: const ValueKey('group-description-field'),
                label: strings.groupDescriptionLabel,
                controller: _description,
                maxLength: GroupMetadata.maximumDescriptionScalars,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.x4),
              AppButton(
                label: _photoSelected
                    ? strings.groupPhotoSelected
                    : strings.groupPhotoAction,
                leading: AppIcons.attach,
                kind: AppButtonKind.outline,
                onPressed: _busy
                    ? null
                    : () => setState(() => _photoSelected = !_photoSelected),
              ),
            ] else
              GroupMemberPicker(
                contacts: widget.contacts,
                selectedUserIds: _selected,
                maximumSelection: GroupState.maximumMembers - 1,
                onSelectionChanged: (next) => setState(() {
                  _selected
                    ..clear()
                    ..addAll(next);
                  _error = null;
                }),
              ),
            if (_error case final error?) ...[
              const SizedBox(height: AppSpacing.x4),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: context.tokens.typography.compact.copyWith(
                    color: context.tokens.colors.danger,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.x6),
            if (_busy)
              AppStatePanel.loading(title: strings.groupCreatingState)
            else
              AppButton(
                key: ValueKey(_details ? 'group-create' : 'group-next'),
                label: _details
                    ? strings.groupCreateAction
                    : strings.groupNextAction,
                onPressed: _details ? _create : _next,
              ),
          ],
        ),
      ),
    );
  }

  void _next() {
    final strings = AppLocalizations.of(context);
    if (_selected.isEmpty) {
      setState(() => _error = strings.groupSelectMemberMessage);
      return;
    }
    if (_selected.length >= GroupState.maximumMembers) {
      setState(() => _error = strings.groupMemberLimitMessage);
      return;
    }
    setState(() {
      _details = true;
      _error = null;
    });
  }

  Future<void> _create() async {
    final strings = AppLocalizations.of(context);
    final metadata = GroupMetadata(
      name: _name.text,
      description: _description.text,
      photoCapability: _photoSelected ? 'development-preview-photo' : null,
    ).normalized();
    if (!metadata.isValid) {
      setState(() => _error = strings.groupNameLabel);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final members = [
      for (final contact in widget.contacts)
        if (_selected.contains(contact.userId))
          GroupMember(
            userId: contact.userId,
            displayName: contact.name,
            role: GroupRole.member,
            verified: contact.verified,
          ),
    ];
    final result = await widget.onCreate(metadata, members);
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        context.go('/groups/${value.groupId}');
      case FailureResult():
        setState(() {
          _busy = false;
          _error = strings.groupCreateFailed;
        });
    }
  }
}

class GroupMemberPicker extends StatefulWidget {
  const GroupMemberPicker({
    required this.contacts,
    required this.selectedUserIds,
    required this.onSelectionChanged,
    this.maximumSelection = GroupState.maximumMembers,
    super.key,
  });

  final List<GroupPickerContact> contacts;
  final Set<String> selectedUserIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final int maximumSelection;

  @override
  State<GroupMemberPicker> createState() => _GroupMemberPickerState();
}

class _GroupMemberPickerState extends State<GroupMemberPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.contacts
        .where((contact) => contact.name.toLowerCase().contains(query))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          key: const ValueKey('group-member-search'),
          label: strings.groupSearchMembersLabel,
          controller: _search,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          strings.groupSelectedCount(widget.selectedUserIds.length),
          style: context.tokens.typography.compact.copyWith(
            color: context.tokens.colors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        if (filtered.isEmpty)
          AppStatePanel.empty(
            title: strings.groupMemberPickerEmpty,
            message: strings.contactsEmptyMessage,
          )
        else
          for (final contact in filtered)
            Semantics(
              checked: widget.selectedUserIds.contains(contact.userId),
              child: CheckboxListTile(
                key: ValueKey('group-picker-${contact.userId}'),
                value: widget.selectedUserIds.contains(contact.userId),
                controlAffinity: ListTileControlAffinity.leading,
                secondary: ContactAvatar(
                  username: contact.name,
                  semanticLabel: contact.name,
                  authenticatedSeed: _avatarSeed(contact.userId),
                ),
                title: Text(contact.name),
                subtitle: contact.verified
                    ? Text(strings.groupVerifiedMember)
                    : null,
                onChanged: (selected) {
                  final next = {...widget.selectedUserIds};
                  if (selected ?? false) {
                    if (next.length >= widget.maximumSelection) return;
                    next.add(contact.userId);
                  } else {
                    next.remove(contact.userId);
                  }
                  widget.onSelectionChanged(next);
                },
              ),
            ),
      ],
    );
  }
}

class GroupChatPage extends ConsumerWidget {
  const GroupChatPage({
    required this.groupId,
    this.injectedState,
    this.injectedMessages,
    this.currentUserId,
    this.onSend,
    super.key,
  });

  final String groupId;
  final GroupState? injectedState;
  final List<GroupMessage>? injectedMessages;
  final String? currentUserId;
  final SendGroupMessageCallback? onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (injectedState != null && injectedMessages != null && onSend != null) {
      return GroupChatView(
        state: injectedState!,
        messages: injectedMessages!,
        currentUserId: currentUserId ?? injectedState!.members.first.userId,
        onSend: onSend!,
      );
    }
    if (ref.watch(groupFeatureAvailabilityProvider) !=
        GroupFeatureAvailability.developmentPreview) {
      return const GroupProductionGatePage();
    }
    final auth = ref.watch(authenticationControllerProvider);
    final userId = currentUserId ?? auth.userId;
    if (userId == null) return const GroupProductionGatePage();
    final group = ref.watch(groupProvider(groupId));
    final messages = ref.watch(groupMessagesProvider(groupId));
    final device = ref.watch(currentMessagingDeviceIdProvider);
    final useCases = ref.watch(groupUseCasesProvider);
    return group.when(
      loading: () => _loadingPage(context),
      error: (_, _) => _errorPage(context),
      data: (state) {
        if (state == null) return _errorPage(context);
        return messages.when(
          loading: () => _loadingPage(context),
          error: (_, _) => _errorPage(context),
          data: (items) => device.when(
            loading: () => _loadingPage(context),
            error: (_, _) => _errorPage(context),
            data: (deviceId) => useCases.when(
              loading: () => _loadingPage(context),
              error: (_, _) => _errorPage(context),
              data: (resolved) => GroupChatView(
                state: state,
                messages: items,
                currentUserId: userId,
                onSend: (text) => resolved.sendMessage(
                  groupId: groupId,
                  senderUserId: userId,
                  senderDeviceId: deviceId,
                  text: text,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class GroupChatView extends StatefulWidget {
  const GroupChatView({
    required this.state,
    required this.messages,
    required this.currentUserId,
    required this.onSend,
    super.key,
  });

  final GroupState state;
  final List<GroupMessage> messages;
  final String currentUserId;
  final SendGroupMessageCallback onSend;

  @override
  State<GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<GroupChatView> {
  final _composerKey = GlobalKey<ChatComposerBuilderState>();
  var _sending = false;
  var _sendFailed = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = widget.state;
    final gate = _chatGate(state.lifecycle);
    final viewMessages = <ChatMessageViewModel>[
      for (var index = 0; index < widget.messages.length; index++)
        _messageView(widget.messages[index], index),
    ];
    final timeline = ChatTimelineViewModel(
      state: viewMessages.isEmpty
          ? ChatTimelineLoadState.empty
          : ChatTimelineLoadState.data,
      conversationId: state.groupId,
      title: state.metadata.name,
      savedMessages: false,
      securityGate: gate,
      offline: false,
      hasMoreBefore: false,
      loadingBefore: false,
      olderLoadFailed: false,
      presenceOnline: false,
      typing: false,
      pinnedMessageIds: const [],
      messages: viewMessages,
    );
    final chat = Column(
      children: [
        const _DevelopmentPreviewBanner(),
        if (state.lifecycle != GroupLifecycle.active)
          _GroupLifecycleNotice(lifecycle: state.lifecycle),
        if (_sendFailed) _InlineError(message: strings.groupSendFailed),
        Expanded(
          child: ChatTimelineAdapter(model: timeline, onIntent: _handleIntent),
        ),
        if (_sending)
          const LinearProgressIndicator(minHeight: 2)
        else
          ChatComposerBuilder(
            key: _composerKey,
            securityGate: gate,
            offline: false,
            savedMessages: false,
            onIntent: _handleIntent,
          ),
      ],
    );
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      key: const ValueKey('group-chat-screen'),
      appBar: AppBar(
        title: InkWell(
          onTap: () => context.push('/groups/${state.groupId}/info'),
          child: Semantics(
            button: true,
            label: strings.groupInfoTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.metadata.name, maxLines: 1),
                Text(
                  strings.groupMemberCount(state.activeMembers.length),
                  style: context.tokens.typography.label,
                ),
              ],
            ),
          ),
        ),
        actions: [
          AppIconButton(
            icon: AppIcons.info,
            semanticLabel: strings.groupInfoTitle,
            onPressed: () => context.push('/groups/${state.groupId}/info'),
            kind: AppButtonKind.ghost,
          ),
        ],
      ),
      body: width >= 1000
          ? Row(
              children: [
                Expanded(child: chat),
                SizedBox(
                  width: 360,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.tokens.colors.surface,
                      border: BorderDirectional(
                        start: BorderSide(color: context.tokens.colors.border),
                      ),
                    ),
                    child: _GroupInfoSummary(state: state),
                  ),
                ),
              ],
            )
          : chat,
    );
  }

  ChatMessageViewModel _messageView(GroupMessage message, int index) {
    final member = widget.state.member(message.senderUserId);
    final outgoing =
        message.senderUserId.toLowerCase() ==
        widget.currentUserId.toLowerCase();
    final previous = index == 0 ? null : widget.messages[index - 1];
    final next = index == widget.messages.length - 1
        ? null
        : widget.messages[index + 1];
    return ChatMessageViewModel(
      id: message.messageId,
      authorId: message.senderUserId,
      authorName: member?.displayName ?? message.senderUserId,
      outgoing: outgoing,
      kind: ChatTimelineContentKind.text,
      text: message.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        message.createdMs,
        isUtc: true,
      ).toLocal(),
      delivery: message.localPreviewOnly
          ? ChatDeliveryViewState.localOnly
          : ChatDeliveryViewState.queued,
      firstInAuthorGroup:
          previous == null || previous.senderUserId != message.senderUserId,
      lastInAuthorGroup:
          next == null || next.senderUserId != message.senderUserId,
      edited: false,
      deleted: false,
      pinned: false,
      starred: false,
      unread: false,
      timestampSkewed: false,
      canEdit: false,
      canDeleteForEveryone: false,
    );
  }

  void _handleIntent(ChatIntent intent) {
    _composerKey.currentState?.handleIntent(intent);
    if (intent case SendTextIntent(:final text)) {
      unawaited(_send(text));
    }
  }

  Future<void> _send(String text) async {
    setState(() {
      _sending = true;
      _sendFailed = false;
    });
    final result = await widget.onSend(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sendFailed = result is FailureResult<GroupMessage>;
    });
  }
}

class GroupInfoPage extends ConsumerWidget {
  const GroupInfoPage({
    required this.groupId,
    this.injectedState,
    this.currentUserId,
    this.onMutate,
    super.key,
  });

  final String groupId;
  final GroupState? injectedState;
  final String? currentUserId;
  final MutateGroupCallback? onMutate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (injectedState != null && onMutate != null) {
      return GroupInfoView(
        state: injectedState!,
        currentUserId: currentUserId ?? injectedState!.members.first.userId,
        onMutate: onMutate!,
      );
    }
    if (ref.watch(groupFeatureAvailabilityProvider) !=
        GroupFeatureAvailability.developmentPreview) {
      return const GroupProductionGatePage();
    }
    final auth = ref.watch(authenticationControllerProvider);
    final userId = currentUserId ?? auth.userId;
    if (userId == null) return const GroupProductionGatePage();
    final state = ref.watch(groupProvider(groupId));
    final device = ref.watch(currentMessagingDeviceIdProvider);
    final useCases = ref.watch(groupUseCasesProvider);
    return state.when(
      loading: () => _loadingPage(context),
      error: (_, _) => _errorPage(context),
      data: (group) {
        if (group == null) return _errorPage(context);
        return device.when(
          loading: () => _loadingPage(context),
          error: (_, _) => _errorPage(context),
          data: (deviceId) => useCases.when(
            loading: () => _loadingPage(context),
            error: (_, _) => _errorPage(context),
            data: (resolved) => GroupInfoView(
              state: group,
              currentUserId: userId,
              onMutate: (operation) => resolved.mutate(
                groupId: groupId,
                actorUserId: userId,
                actorDeviceId: deviceId,
                operation: operation,
              ),
            ),
          ),
        );
      },
    );
  }
}

class GroupInfoView extends StatefulWidget {
  const GroupInfoView({
    required this.state,
    required this.currentUserId,
    required this.onMutate,
    this.embedded = false,
    super.key,
  });

  final GroupState state;
  final String currentUserId;
  final MutateGroupCallback onMutate;
  final bool embedded;

  @override
  State<GroupInfoView> createState() => _GroupInfoViewState();
}

class _GroupInfoViewState extends State<GroupInfoView> {
  var _busy = false;
  var _failed = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final state = widget.state;
    final canEdit = GroupAuthorization.allows(
      state,
      widget.currentUserId,
      GroupPermission.editMetadata,
    );
    final content = _ResponsiveBody(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.x4),
        children: [
          const _DevelopmentPreviewBanner(),
          if (state.lifecycle != GroupLifecycle.active) ...[
            const SizedBox(height: AppSpacing.x3),
            _GroupLifecycleNotice(lifecycle: state.lifecycle),
          ],
          const SizedBox(height: AppSpacing.x6),
          _GroupInfoSummary(state: state),
          const SizedBox(height: AppSpacing.x6),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              AppButton(
                label: strings.groupMuteAction,
                leading: AppIcons.muted,
                onPressed: null,
                kind: AppButtonKind.outline,
              ),
              AppButton(
                label: strings.groupSearchChatAction,
                leading: AppIcons.search,
                onPressed: null,
                kind: AppButtonKind.outline,
              ),
              AppButton(
                label: strings.groupSharedMediaAction,
                leading: AppIcons.attach,
                onPressed: null,
                kind: AppButtonKind.outline,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          Text(
            strings.groupMembersSection,
            style: context.tokens.typography.section,
          ),
          const SizedBox(height: AppSpacing.x2),
          for (final member in state.members.where((member) => member.isActive))
            _MemberRow(member: member, onTap: () => _showMember(member)),
          if (GroupAuthorization.allows(
            state,
            widget.currentUserId,
            GroupPermission.inviteMembers,
          ))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.x3),
              child: AppButton(
                label: strings.groupAddMembersAction,
                leading: AppIcons.add,
                onPressed: () =>
                    context.push('/groups/${state.groupId}/add-members'),
                kind: AppButtonKind.outline,
              ),
            ),
          if (_busy) ...[
            const SizedBox(height: AppSpacing.x4),
            const LinearProgressIndicator(),
          ],
          if (_failed) ...[
            const SizedBox(height: AppSpacing.x3),
            _InlineError(message: strings.groupActionFailed),
          ],
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            label: strings.groupLeaveAction,
            leading: AppIcons.delete,
            kind: AppButtonKind.danger,
            onPressed: GroupAuthorization.canLeave(state, widget.currentUserId)
                ? _confirmLeave
                : null,
          ),
          if (!GroupAuthorization.canLeave(state, widget.currentUserId) &&
              state.member(widget.currentUserId)?.role == GroupRole.owner)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.x2),
              child: Text(
                strings.groupOwnerMustTransfer,
                style: context.tokens.typography.compact.copyWith(
                  color: context.tokens.colors.warning,
                ),
              ),
            ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      key: const ValueKey('group-info-screen'),
      appBar: AppBar(
        title: Text(strings.groupInfoTitle),
        actions: [
          if (canEdit)
            AppIconButton(
              icon: AppIcons.edit,
              semanticLabel: strings.groupEditAction,
              kind: AppButtonKind.ghost,
              onPressed: () => context.push('/groups/${state.groupId}/edit'),
            ),
        ],
      ),
      body: content,
    );
  }

  Future<void> _showMember(GroupMember member) => showAppSheet<void>(
    context: context,
    semanticLabel: member.displayName,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(member.displayName, style: context.tokens.typography.section),
        const SizedBox(height: AppSpacing.x3),
        AppButton(
          label: AppLocalizations.of(context).contactMessageAction,
          onPressed: () {
            Navigator.pop(context);
            unawaited(context.push('/chats/direct/${member.userId}'));
          },
          kind: AppButtonKind.outline,
        ),
        if (GroupAuthorization.canRemove(
          widget.state,
          actorUserId: widget.currentUserId,
          targetUserId: member.userId,
        )) ...[
          const SizedBox(height: AppSpacing.x2),
          AppButton(
            label: AppLocalizations.of(context).groupRemoveAction,
            kind: AppButtonKind.danger,
            onPressed: () {
              Navigator.pop(context);
              unawaited(_confirmRemove(member));
            },
          ),
        ],
        if (GroupAuthorization.canChangeRole(
          widget.state,
          actorUserId: widget.currentUserId,
          targetUserId: member.userId,
          role: member.role == GroupRole.admin
              ? GroupRole.member
              : GroupRole.admin,
        )) ...[
          const SizedBox(height: AppSpacing.x2),
          AppButton(
            label: member.role == GroupRole.admin
                ? AppLocalizations.of(context).groupDemoteAction
                : AppLocalizations.of(context).groupPromoteAction,
            onPressed: () {
              Navigator.pop(context);
              unawaited(
                _mutate(
                  ChangeGroupRoleOperation(
                    targetUserId: member.userId,
                    role: member.role == GroupRole.admin
                        ? GroupRole.member
                        : GroupRole.admin,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.x2),
          AppButton(
            label: AppLocalizations.of(context).groupTransferOwnerAction,
            onPressed: () {
              Navigator.pop(context);
              unawaited(
                _mutate(TransferGroupOwnershipOperation(member.userId)),
              );
            },
            kind: AppButtonKind.outline,
          ),
        ],
      ],
    ),
  );

  Future<void> _confirmRemove(GroupMember member) async {
    final strings = AppLocalizations.of(context);
    await showAppDialog<void>(
      context: context,
      title: strings.groupConfirmRemoveTitle,
      body: strings.groupConfirmRemoveBody,
      actions: [
        AppButton(
          label: strings.groupCancelAction,
          kind: AppButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: strings.groupRemoveAction,
          kind: AppButtonKind.danger,
          onPressed: () {
            Navigator.pop(context);
            unawaited(_mutate(RemoveGroupMemberOperation(member.userId)));
          },
        ),
      ],
    );
  }

  Future<void> _confirmLeave() async {
    final strings = AppLocalizations.of(context);
    await showAppDialog<void>(
      context: context,
      title: strings.groupConfirmLeaveTitle,
      body: strings.groupConfirmLeaveBody,
      actions: [
        AppButton(
          label: strings.groupCancelAction,
          kind: AppButtonKind.ghost,
          onPressed: () => Navigator.pop(context),
        ),
        AppButton(
          label: strings.groupLeaveAction,
          kind: AppButtonKind.danger,
          onPressed: () {
            Navigator.pop(context);
            unawaited(_mutate(const LeaveGroupOperation()));
          },
        ),
      ],
    );
  }

  Future<void> _mutate(GroupControlOperation operation) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final result = await widget.onMutate(operation);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = result is FailureResult<GroupState>;
    });
  }
}

class EditGroupPage extends ConsumerWidget {
  const EditGroupPage({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(groupFeatureAvailabilityProvider) !=
        GroupFeatureAvailability.developmentPreview) {
      return const GroupProductionGatePage();
    }
    final auth = ref.watch(authenticationControllerProvider);
    final userId = auth.userId;
    if (userId == null) return const GroupProductionGatePage();
    final group = ref.watch(groupProvider(groupId));
    final device = ref.watch(currentMessagingDeviceIdProvider);
    final useCases = ref.watch(groupUseCasesProvider);
    return group.when(
      loading: () => _loadingPage(context),
      error: (_, _) => _errorPage(context),
      data: (state) {
        if (state == null) return _errorPage(context);
        return device.when(
          loading: () => _loadingPage(context),
          error: (_, _) => _errorPage(context),
          data: (deviceId) => useCases.when(
            loading: () => _loadingPage(context),
            error: (_, _) => _errorPage(context),
            data: (resolved) => GroupEditView(
              state: state,
              currentUserId: userId,
              onMutate: (operation) => resolved.mutate(
                groupId: groupId,
                actorUserId: userId,
                actorDeviceId: deviceId,
                operation: operation,
              ),
            ),
          ),
        );
      },
    );
  }
}

class GroupEditView extends StatefulWidget {
  const GroupEditView({
    required this.state,
    required this.currentUserId,
    required this.onMutate,
    super.key,
  });

  final GroupState state;
  final String currentUserId;
  final MutateGroupCallback onMutate;

  @override
  State<GroupEditView> createState() => _GroupEditViewState();
}

class _GroupEditViewState extends State<GroupEditView> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late GroupInvitationPolicy _invitationPolicy;
  late bool _shareHistory;
  var _busy = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.state.metadata.name);
    _description = TextEditingController(
      text: widget.state.metadata.description,
    );
    _invitationPolicy = widget.state.invitationPolicy;
    _shareHistory =
        widget.state.historySharingPolicy ==
        GroupHistorySharingPolicy.reshareAvailable;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final canEdit = GroupAuthorization.allows(
      widget.state,
      widget.currentUserId,
      GroupPermission.editMetadata,
    );
    final isOwner = GroupAuthorization.allows(
      widget.state,
      widget.currentUserId,
      GroupPermission.editHistorySharingPolicy,
    );
    return Scaffold(
      key: const ValueKey('group-edit-screen'),
      appBar: AppBar(title: Text(strings.groupEditTitle)),
      body: _ResponsiveBody(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.x4),
          children: [
            const _DevelopmentPreviewBanner(),
            const SizedBox(height: AppSpacing.x4),
            if (!canEdit) _InlineError(message: strings.groupPermissionChanged),
            AppField(
              label: strings.groupNameLabel,
              controller: _name,
              enabled: canEdit && !_busy,
              maxLength: GroupMetadata.maximumNameScalars,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppField(
              label: strings.groupDescriptionLabel,
              controller: _description,
              enabled: canEdit && !_busy,
              maxLength: GroupMetadata.maximumDescriptionScalars,
            ),
            const SizedBox(height: AppSpacing.x6),
            Text(
              strings.groupInvitePolicyLabel,
              style: context.tokens.typography.compact,
            ),
            DropdownButtonFormField<GroupInvitationPolicy>(
              key: const ValueKey('group-invite-policy'),
              initialValue: _invitationPolicy,
              items: [
                for (final policy in GroupInvitationPolicy.values)
                  DropdownMenuItem(
                    value: policy,
                    child: Text(_invitationLabel(strings, policy)),
                  ),
              ],
              onChanged: isOwner && !_busy
                  ? (value) => setState(() => _invitationPolicy = value!)
                  : null,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppCheckboxRow(
              value: _shareHistory,
              label: strings.groupHistorySharingLabel,
              onChanged: isOwner && !_busy
                  ? (value) => setState(() => _shareHistory = value)
                  : null,
            ),
            Text(
              strings.groupHistorySharingNote,
              style: context.tokens.typography.compact.copyWith(
                color: context.tokens.colors.textMuted,
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: AppSpacing.x4),
              _InlineError(message: strings.groupActionFailed),
            ],
            const SizedBox(height: AppSpacing.x6),
            if (_busy)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: AppSpacing.x2,
                runSpacing: AppSpacing.x2,
                alignment: WrapAlignment.end,
                children: [
                  AppButton(
                    label: strings.groupCancelAction,
                    kind: AppButtonKind.ghost,
                    onPressed: () => context.pop(),
                  ),
                  AppButton(
                    key: const ValueKey('group-save'),
                    label: strings.groupSaveAction,
                    onPressed: canEdit ? _save : null,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final metadata = GroupMetadata(
      name: _name.text,
      description: _description.text,
      photoCapability: widget.state.metadata.photoCapability,
    ).normalized();
    Result<GroupState> result = await widget.onMutate(
      UpdateGroupMetadataOperation(metadata),
    );
    if (result is Success<GroupState> &&
        GroupAuthorization.allows(
          widget.state,
          widget.currentUserId,
          GroupPermission.editHistorySharingPolicy,
        )) {
      result = await widget.onMutate(
        UpdateGroupPoliciesOperation(
          invitationPolicy: _invitationPolicy,
          historySharingPolicy: _shareHistory
              ? GroupHistorySharingPolicy.reshareAvailable
              : GroupHistorySharingPolicy.newMessagesOnly,
        ),
      );
    }
    if (!mounted) return;
    if (result is Success<GroupState>) {
      context.pop();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }
}

class AddGroupMembersPage extends ConsumerStatefulWidget {
  const AddGroupMembersPage({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<AddGroupMembersPage> createState() =>
      _AddGroupMembersPageState();
}

class _AddGroupMembersPageState extends ConsumerState<AddGroupMembersPage> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    if (ref.watch(groupFeatureAvailabilityProvider) !=
        GroupFeatureAvailability.developmentPreview) {
      return const GroupProductionGatePage();
    }
    final auth = ref.watch(authenticationControllerProvider);
    final userId = auth.userId;
    if (userId == null) return const GroupProductionGatePage();
    final group = ref.watch(groupProvider(widget.groupId));
    final contacts = ref.watch(contactListProvider(userId));
    final device = ref.watch(currentMessagingDeviceIdProvider);
    final useCases = ref.watch(groupUseCasesProvider);
    if (group case AsyncData(value: final state?)) {
      if (contacts case AsyncData(value: final contactValues)) {
        if (device case AsyncData(value: final deviceId)) {
          if (useCases case AsyncData(value: final resolved)) {
            final existing = state.members
                .map((member) => member.userId)
                .toSet();
            final eligible = contactValues
                .where((contact) => !existing.contains(contact.userId))
                .map(GroupPickerContact.fromContact)
                .toList(growable: false);
            return Scaffold(
              appBar: AppBar(
                title: Text(AppLocalizations.of(context).groupAddMembersAction),
              ),
              body: _ResponsiveBody(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  children: [
                    const _DevelopmentPreviewBanner(),
                    const SizedBox(height: AppSpacing.x4),
                    GroupMemberPicker(
                      contacts: eligible,
                      selectedUserIds: _selected,
                      maximumSelection:
                          GroupState.maximumMembers -
                          state.activeMembers.length,
                      onSelectionChanged: (value) => setState(() {
                        _selected
                          ..clear()
                          ..addAll(value);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.x6),
                    AppButton(
                      label: AppLocalizations.of(context).groupAddMembersAction,
                      onPressed: _selected.isEmpty
                          ? null
                          : () async {
                              final members = [
                                for (final contact in eligible)
                                  if (_selected.contains(contact.userId))
                                    GroupMember(
                                      userId: contact.userId,
                                      displayName: contact.name,
                                      role: GroupRole.member,
                                      verified: contact.verified,
                                    ),
                              ];
                              final result = await resolved.mutate(
                                groupId: widget.groupId,
                                actorUserId: userId,
                                actorDeviceId: deviceId,
                                operation: InviteGroupMembersOperation(members),
                              );
                              if (mounted && result is Success<GroupState>) {
                                this.context.pop();
                              }
                            },
                    ),
                  ],
                ),
              ),
            );
          }
        }
      }
    }
    return _loadingPage(context);
  }
}

class GroupProductionGatePage extends StatelessWidget {
  const GroupProductionGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('group-production-gate'),
      appBar: AppBar(title: Text(strings.groupInfoTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppStatePanel.error(
              title: strings.groupProductionUnavailableTitle,
              message: strings.groupProductionUnavailableMessage,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupInfoSummary extends StatelessWidget {
  const _GroupInfoSummary({required this.state});
  final GroupState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label:
          '${state.metadata.name}, '
          '${strings.groupMemberCount(state.activeMembers.length)}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ContactAvatar(
            username: state.metadata.name,
            semanticLabel: state.metadata.name,
            authenticatedSeed: _avatarSeed(state.groupId),
            radius: 44,
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            state.metadata.name,
            style: context.tokens.typography.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            state.metadata.description.isEmpty
                ? strings.groupNoDescription
                : state.metadata.description,
            style: context.tokens.typography.body.copyWith(
              color: context.tokens.colors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x2),
          AppStatusBadge(
            kind: AppStatusKind.neutral,
            label: strings.groupMemberCount(state.activeMembers.length),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final GroupMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Semantics(
      key: ValueKey('group-member-${member.userId}'),
      button: true,
      label: '${member.displayName}, ${_roleLabel(strings, member.role)}',
      child: ListTile(
        minTileHeight: AppFocus.minimumTarget,
        leading: ContactAvatar(
          username: member.displayName,
          semanticLabel: member.displayName,
          authenticatedSeed: _avatarSeed(member.userId),
        ),
        title: Text(member.displayName),
        subtitle: member.verified ? Text(strings.groupVerifiedMember) : null,
        trailing: AppStatusBadge(
          kind: member.role == GroupRole.owner
              ? AppStatusKind.information
              : AppStatusKind.neutral,
          label: _roleLabel(strings, member.role),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DevelopmentPreviewBanner extends StatelessWidget {
  const _DevelopmentPreviewBanner();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.colors.warning.withValues(alpha: 0.14),
        borderRadius: AppRadii.compact,
        border: Border.all(color: context.tokens.colors.warning),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Row(
          children: [
            AppIcon(AppIcons.warning, color: context.tokens.colors.warning),
            const SizedBox(width: AppSpacing.x2),
            Expanded(
              child: Text(
                AppLocalizations.of(context).groupDevelopmentPreviewBanner,
                style: context.tokens.typography.compact,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GroupLifecycleNotice extends StatelessWidget {
  const _GroupLifecycleNotice({required this.lifecycle});
  final GroupLifecycle lifecycle;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final message = switch (lifecycle) {
      GroupLifecycle.active => '',
      GroupLifecycle.membershipUpdating => strings.groupMembershipUpdatingState,
      GroupLifecycle.removed => strings.groupRemovedState,
      GroupLifecycle.left => strings.groupLeftState,
      GroupLifecycle.queueGapRejoinRequired => strings.groupQueueGapState,
      GroupLifecycle.forkQuarantined => strings.groupForkState,
      GroupLifecycle.controlQuarantined => strings.groupControlQuarantineState,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ColoredBox(
        color: context.tokens.colors.warning.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Text(message, style: context.tokens.typography.compact),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: context.tokens.typography.compact.copyWith(
        color: context.tokens.colors.danger,
      ),
    ),
  );
}

class _ResponsiveBody extends StatelessWidget {
  const _ResponsiveBody({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}

Widget _loadingPage(BuildContext context) => Scaffold(
  body: Center(
    child: AppStatePanel.loading(
      title: AppLocalizations.of(context).contactsLoadingTitle,
    ),
  ),
);

Widget _errorPage(BuildContext context) => Scaffold(
  body: Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.x6),
      child: AppStatePanel.error(
        title: AppLocalizations.of(context).chatsErrorTitle,
        message: AppLocalizations.of(context).groupActionFailed,
      ),
    ),
  ),
);

String _roleLabel(AppLocalizations strings, GroupRole role) => switch (role) {
  GroupRole.owner => strings.groupRoleOwner,
  GroupRole.admin => strings.groupRoleAdmin,
  GroupRole.member => strings.groupRoleMember,
};

String _invitationLabel(
  AppLocalizations strings,
  GroupInvitationPolicy policy,
) => switch (policy) {
  GroupInvitationPolicy.ownerOnly => strings.groupInviteOwnerOnly,
  GroupInvitationPolicy.ownerAndAdmins => strings.groupInviteAdmins,
  GroupInvitationPolicy.allMembers => strings.groupInviteEveryone,
};

ChatSecurityGate _chatGate(GroupLifecycle lifecycle) => switch (lifecycle) {
  GroupLifecycle.active => ChatSecurityGate.ready,
  GroupLifecycle.membershipUpdating => ChatSecurityGate.groupUpdating,
  GroupLifecycle.removed ||
  GroupLifecycle.left => ChatSecurityGate.groupRemoved,
  GroupLifecycle.queueGapRejoinRequired => ChatSecurityGate.groupQueueGap,
  GroupLifecycle.forkQuarantined ||
  GroupLifecycle.controlQuarantined => ChatSecurityGate.groupConflict,
};

int _avatarSeed(String value) => value.codeUnits.fold<int>(
  0,
  (seed, unit) => ((seed * 31) + unit) & 0x7fffffff,
);
