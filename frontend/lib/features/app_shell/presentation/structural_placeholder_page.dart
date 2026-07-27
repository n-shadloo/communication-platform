import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum StructuralPlaceholderKind {
  chats,
  voiceRooms,
  settings,
  thread,
  room,
  appearance,
  newChat,
  newRoom,
}

class StructuralPlaceholderPage extends StatelessWidget {
  const StructuralPlaceholderPage({required this.kind, super.key});

  final StructuralPlaceholderKind kind;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (kind) {
      StructuralPlaceholderKind.chats => l10n.chatsPlaceholderTitle,
      StructuralPlaceholderKind.voiceRooms => l10n.voiceRoomsPlaceholderTitle,
      StructuralPlaceholderKind.settings => l10n.settingsPlaceholderTitle,
      StructuralPlaceholderKind.thread => l10n.threadPlaceholderTitle,
      StructuralPlaceholderKind.room => l10n.roomPlaceholderTitle,
      StructuralPlaceholderKind.appearance => l10n.appearancePlaceholderTitle,
      StructuralPlaceholderKind.newChat => l10n.newChatPlaceholderTitle,
      StructuralPlaceholderKind.newRoom => l10n.newRoomPlaceholderTitle,
    };
    final body = switch (kind) {
      StructuralPlaceholderKind.chats => l10n.chatsPlaceholderBody,
      StructuralPlaceholderKind.voiceRooms => l10n.voiceRoomsPlaceholderBody,
      StructuralPlaceholderKind.settings => l10n.settingsPlaceholderBody,
      _ => l10n.placeholderBody,
    };
    final icon = switch (kind) {
      StructuralPlaceholderKind.chats ||
      StructuralPlaceholderKind.thread ||
      StructuralPlaceholderKind.newChat => AppIcons.chats,
      StructuralPlaceholderKind.voiceRooms ||
      StructuralPlaceholderKind.room ||
      StructuralPlaceholderKind.newRoom => AppIcons.voiceRooms,
      StructuralPlaceholderKind.settings ||
      StructuralPlaceholderKind.appearance => AppIcons.settings,
    };
    final route = GoRouterState.of(context).uri.path;

    return ColoredBox(
      color: context.tokens.colors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppContentWidths.readable,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.x6),
            child: Semantics(
              container: true,
              header: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppStatusBadge(
                      kind: AppStatusKind.warning,
                      label: l10n.nonShippingPlaceholder,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  AppIcon(icon, color: context.tokens.colors.accent, size: 40),
                  const SizedBox(height: AppSpacing.x4),
                  Text(
                    title,
                    style: context.tokens.typography.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Text(
                    body,
                    style: context.tokens.typography.body.copyWith(
                      color: context.tokens.colors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Text(
                    l10n.routeLabel(route),
                    key: const ValueKey('current-route-label'),
                    style: context.tokens.typography.compact.copyWith(
                      color: context.tokens.colors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_targetRoute case final target?) ...[
                    const SizedBox(height: AppSpacing.x6),
                    AppButton(
                      label: kind == StructuralPlaceholderKind.settings
                          ? l10n.openAppearanceDetail
                          : l10n.openPlaceholderDetail,
                      onPressed: () => context.go(target),
                      leading: AppIcons.forward,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _targetRoute => switch (kind) {
    StructuralPlaceholderKind.chats => '/chats/sample-thread',
    StructuralPlaceholderKind.voiceRooms => '/voice-rooms/sample-room',
    StructuralPlaceholderKind.settings => '/settings/appearance',
    _ => null,
  };
}
