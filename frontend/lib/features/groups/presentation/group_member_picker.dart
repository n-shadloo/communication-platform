import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/presentation/group_callbacks.dart';
import 'package:communication_platform/features/groups/presentation/group_components.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

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
                  authenticatedSeed: groupAvatarSeed(contact.userId),
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
