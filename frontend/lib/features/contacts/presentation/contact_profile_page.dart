import 'dart:async';

import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/features/contacts/presentation/contact_components.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ContactProfilePage extends ConsumerStatefulWidget {
  const ContactProfilePage({required this.userId, this.contact, super.key});

  final String userId;
  final ContactProjection? contact;

  @override
  ConsumerState<ContactProfilePage> createState() => _ContactProfilePageState();
}

class _ContactProfilePageState extends ConsumerState<ContactProfilePage> {
  @override
  void initState() {
    super.initState();
    if (widget.contact == null) {
      unawaited(_refreshAuthenticatedProfile());
    }
  }

  Future<void> _refreshAuthenticatedProfile() async {
    final service = await ref.read(profileServiceProvider.future);
    await service.refreshPeer(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contact != null) return _body(context, widget.contact);
    final value = ref.watch(contactProvider(widget.userId));
    return value.when(
      data: (contact) => _body(context, contact),
      loading: () => Scaffold(
        body: AppStatePanel.loading(
          title: AppLocalizations.of(context).contactsLoadingTitle,
        ),
      ),
      error: (_, _) => _body(context, null),
    );
  }

  Widget _body(BuildContext context, ContactProjection? contact) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: strings.authBackAction,
          onPressed: () => context.pop(),
          kind: AppButtonKind.ghost,
        ),
        title: Text(strings.contactProfileTitle),
      ),
      body: contact == null
          ? AppStatePanel.empty(
              title: strings.contactsEmptyTitle,
              message: strings.contactsEmptyMessage,
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.x6),
              children: [
                Center(
                  child: ContactAvatar(
                    username: contact.username,
                    authenticatedSeed: contact.authenticatedAvatarSeed,
                    semanticLabel: contact.presentationName,
                    radius: 48,
                  ),
                ),
                const SizedBox(height: AppSpacing.x4),
                Text(
                  contact.presentationName,
                  style: context.tokens.typography.title,
                  textAlign: TextAlign.center,
                ),
                if (contact.presentationName != contact.username)
                  Text(
                    '@${contact.username}',
                    style: context.tokens.typography.body.copyWith(
                      color: context.tokens.colors.textMuted,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: AppSpacing.x3),
                Center(child: _TrustBadge(state: contact.trustState)),
                if (contact.sensitiveActionsBlocked) ...[
                  const SizedBox(height: AppSpacing.x4),
                  Notice(
                    kind: AppStatusKind.danger,
                    message: strings.contactSensitiveBlocked,
                  ),
                ],
                const SizedBox(height: AppSpacing.x6),
                ActionRow(
                  label: strings.contactMessageAction,
                  icon: AppIcons.chats,
                  onTap: contact.sensitiveActionsBlocked ? null : () {},
                ),
                ActionRow(
                  label: strings.contactMuteAction,
                  icon: AppIcons.info,
                  onTap: null,
                ),
                ActionRow(
                  key: const ValueKey('contact-verify-action'),
                  label: strings.contactVerifyAction,
                  icon: AppIcons.security,
                  onTap: () =>
                      context.push('/contacts/${widget.userId}/safety'),
                ),
                ActionRow(
                  label: strings.contactSharedMediaAction,
                  icon: AppIcons.info,
                  onTap: null,
                ),
                ActionRow(
                  label: strings.contactClearHistoryAction,
                  icon: AppIcons.warning,
                  onTap: null,
                ),
                ActionRow(
                  label: strings.contactBlockAction,
                  icon: AppIcons.error,
                  onTap: null,
                ),
              ],
            ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.state});

  final ContactTrustState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return AppStatusBadge(
      kind: state == ContactTrustState.verified
          ? AppStatusKind.success
          : state == ContactTrustState.unverified
          ? AppStatusKind.warning
          : AppStatusKind.danger,
      label: state == ContactTrustState.verified
          ? strings.contactsVerified
          : strings.contactsUnverified,
    );
  }
}
