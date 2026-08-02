import 'dart:async';

import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_icons.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/contacts/application/contact_services.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/presentation/contact_avatar.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ContactsNewPage extends ConsumerStatefulWidget {
  const ContactsNewPage({
    this.ownUserId,
    this.contacts,
    this.directoryService,
    super.key,
  });

  final String? ownUserId;
  final Stream<List<ContactProjection>>? contacts;
  final DirectoryService? directoryService;

  @override
  ConsumerState<ContactsNewPage> createState() => _ContactsNewPageState();
}

class _ContactsNewPageState extends ConsumerState<ContactsNewPage> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  var _visible = _pageSize;
  var _refreshing = false;
  var _offline = false;

  @override
  void initState() {
    super.initState();
    if (widget.contacts == null || widget.directoryService != null) {
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final DirectoryService service =
        widget.directoryService ??
        await ref.read(directoryServiceProvider.future);
    final result = await service.refresh();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _offline = switch (result) {
        FailureResult(failure: TransportFailure()) => true,
        _ => false,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ownUserId =
        widget.ownUserId ?? ref.watch(authenticationControllerProvider).userId;
    final injected = widget.contacts;
    if (injected != null) {
      return StreamBuilder<List<ContactProjection>>(
        stream: injected,
        builder: (context, snapshot) =>
            _scaffold(context, snapshot.data, waiting: !snapshot.hasData),
      );
    }
    if (ownUserId == null) {
      return _scaffold(context, const [], waiting: false);
    }
    final contacts = ref.watch(contactListProvider(ownUserId));
    return contacts.when(
      data: (value) => _scaffold(context, value, waiting: false),
      loading: () => _scaffold(context, null, waiting: true),
      error: (_, _) => _scaffold(context, const [], waiting: false),
    );
  }

  Widget _scaffold(
    BuildContext context,
    List<ContactProjection>? contacts, {
    required bool waiting,
  }) {
    final strings = AppLocalizations.of(context);
    final normalized = _search.text.trim().toLowerCase();
    final filtered = (contacts ?? const <ContactProjection>[])
        .where(
          (contact) =>
              normalized.isEmpty ||
              contact.username.contains(normalized) ||
              (contact.canUseAuthenticatedProfile &&
                  contact.presentationName.toLowerCase().contains(normalized)),
        )
        .toList(growable: false);
    final shown = filtered.take(_visible).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: strings.authBackAction,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/chats'),
          kind: AppButtonKind.ghost,
        ),
        title: Text(strings.contactsNewTitle),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey('contacts-new-list'),
          padding: const EdgeInsets.all(AppSpacing.x4),
          children: [
            if (_offline)
              _Notice(
                key: const ValueKey('contacts-offline-cache'),
                kind: AppStatusKind.warning,
                message: strings.contactsOfflineMessage,
              ),
            _ActionRow(
              label: strings.contactsNewGroup,
              icon: AppIcons.add,
              onTap: () => context.push('/groups/new'),
            ),
            _ActionRow(
              label: strings.contactsNewVoiceRoom,
              icon: AppIcons.voiceRooms,
              onTap: null,
            ),
            const SizedBox(height: AppSpacing.x4),
            AppField(
              label: strings.contactsSearchLabel,
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => _visible = _pageSize),
            ),
            const SizedBox(height: AppSpacing.x4),
            if (waiting && contacts == null)
              AppStatePanel.loading(title: strings.contactsLoadingTitle)
            else if (filtered.isEmpty)
              AppStatePanel.empty(
                title: strings.contactsEmptyTitle,
                message: strings.contactsEmptyMessage,
              )
            else ...[
              for (final contact in shown)
                _ContactRow(
                  contact: contact,
                  onTap: () => context.push('/chats/direct/${contact.userId}'),
                ),
              if (shown.length < filtered.length)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x4),
                  child: AppButton(
                    key: const ValueKey('contacts-load-more'),
                    label: strings.contactsLoadMore,
                    onPressed: () => setState(() => _visible += _pageSize),
                    kind: AppButtonKind.outline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

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
                  _Notice(
                    kind: AppStatusKind.danger,
                    message: strings.contactSensitiveBlocked,
                  ),
                ],
                const SizedBox(height: AppSpacing.x6),
                _ActionRow(
                  label: strings.contactMessageAction,
                  icon: AppIcons.chats,
                  onTap: contact.sensitiveActionsBlocked ? null : () {},
                ),
                _ActionRow(
                  label: strings.contactMuteAction,
                  icon: AppIcons.info,
                  onTap: null,
                ),
                _ActionRow(
                  key: const ValueKey('contact-verify-action'),
                  label: strings.contactVerifyAction,
                  icon: AppIcons.security,
                  onTap: () =>
                      context.push('/contacts/${widget.userId}/safety'),
                ),
                _ActionRow(
                  label: strings.contactSharedMediaAction,
                  icon: AppIcons.info,
                  onTap: null,
                ),
                _ActionRow(
                  label: strings.contactClearHistoryAction,
                  icon: AppIcons.warning,
                  onTap: null,
                ),
                _ActionRow(
                  label: strings.contactBlockAction,
                  icon: AppIcons.error,
                  onTap: null,
                ),
              ],
            ),
    );
  }
}

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({this.service, super.key});

  final ProfileService? service;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _name = TextEditingController();
  var _avatarSeed = 0;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = AppLocalizations.of(context);
    final draft = ProfileDraft(
      displayName: _name.text,
      avatarSeed: _avatarSeed,
    );
    if (!draft.isValid) {
      setState(() => _error = strings.profileInvalidName);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ProfileService service =
        widget.service ?? await ref.read(profileServiceProvider.future);
    final result = await service.publishOwn(draft);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = switch (result) {
        FailureResult() => strings.authGenericErrorMessage,
        _ => null,
      };
    });
    if (result case Success()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.profileSavedMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final serviceValue =
        widget.service ?? ref.watch(profileServiceProvider).value;
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: strings.authBackAction,
          onPressed: () => context.pop(),
          kind: AppButtonKind.ghost,
        ),
        title: Text(strings.profileEditTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.x6),
        children: [
          Text(strings.profileVisibilityNote),
          if (serviceValue?.usesTemporaryTransport ?? true) ...[
            const SizedBox(height: AppSpacing.x4),
            _Notice(
              key: const ValueKey('fake-profile-transport-warning'),
              kind: AppStatusKind.warning,
              message: strings.profileTemporaryTransport,
            ),
          ],
          const SizedBox(height: AppSpacing.x6),
          Center(
            child: ContactAvatar(
              username: _name.text.isEmpty ? 'profile' : _name.text,
              authenticatedSeed: _avatarSeed,
              semanticLabel: strings.profileAvatarStyleLabel,
              radius: 48,
            ),
          ),
          const SizedBox(height: AppSpacing.x4),
          AppField(
            label: strings.profileDisplayNameLabel,
            controller: _name,
            maxLength: 64,
            error: _error,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: AppSpacing.x4),
          Text(strings.profileAvatarStyleLabel),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x2,
            runSpacing: AppSpacing.x2,
            children: [
              for (var seed = 0; seed < 8; seed += 1)
                Semantics(
                  selected: _avatarSeed == seed,
                  label: '${strings.profileAvatarStyleLabel} ${seed + 1}',
                  child: ChoiceChip(
                    key: ValueKey('profile-avatar-$seed'),
                    label: ContactAvatar(
                      username: _name.text.isEmpty ? 'profile' : _name.text,
                      authenticatedSeed: seed,
                      semanticLabel:
                          '${strings.profileAvatarStyleLabel} ${seed + 1}',
                      radius: 18,
                    ),
                    selected: _avatarSeed == seed,
                    onSelected: (_) => setState(() => _avatarSeed = seed),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            key: const ValueKey('profile-save'),
            label: _saving
                ? strings.profileSavingAction
                : strings.profileSaveAction,
            onPressed: _saving ? null : _save,
            leading: AppIcons.success,
          ),
        ],
      ),
    );
  }
}

class SafetyNumberPage extends ConsumerStatefulWidget {
  const SafetyNumberPage({
    required this.userId,
    this.authentication,
    this.local,
    super.key,
  });

  final String userId;
  final PeerAuthenticationService? authentication;
  final ContactLocalPort? local;

  @override
  ConsumerState<SafetyNumberPage> createState() => _SafetyNumberPageState();
}

class _SafetyNumberPageState extends ConsumerState<SafetyNumberPage> {
  ContactTrustRecord? _trust;
  SafetyFingerprint? _fingerprint;
  var _busy = true;
  var _confirmedOutOfBand = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
      _confirmedOutOfBand = false;
    });
    final PeerAuthenticationService authentication =
        widget.authentication ??
        await ref.read(peerAuthenticationServiceProvider.future);
    final ContactLocalPort local =
        widget.local ?? await ref.read(contactLocalProvider.future);
    await authentication.refreshPeer(
      userId: widget.userId,
      requirePrekeys: false,
    );
    final trustResult = await local.readTrust(widget.userId);
    final fingerprintResult = await authentication.safetyFingerprint(
      widget.userId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _trust = switch (trustResult) {
        Success<ContactTrustRecord?>(:final value) => value,
        _ => null,
      };
      _fingerprint = switch (fingerprintResult) {
        Success<SafetyFingerprint>(:final value) => value,
        _ => null,
      };
      _failed = _trust == null || _fingerprint == null;
    });
  }

  Future<void> _confirm() async {
    final trust = _trust;
    final identity = trust?.identity;
    if (!_confirmedOutOfBand ||
        identity == null ||
        !_canConfirm(trust!.state)) {
      return;
    }
    setState(() => _busy = true);
    final PeerAuthenticationService authentication =
        widget.authentication ??
        await ref.read(peerAuthenticationServiceProvider.future);
    final result = await authentication.confirmOutOfBand(
      userId: widget.userId,
      exactMasterPublic: identity.masterPublic,
    );
    if (!mounted) return;
    switch (result) {
      case Success(value: final verified):
        setState(() {
          _busy = false;
          _trust = verified;
          _confirmedOutOfBand = false;
          _failed = false;
        });
      case FailureResult():
        await _load();
    }
  }

  bool _canConfirm(ContactTrustState state) =>
      state == ContactTrustState.unverified ||
      state == ContactTrustState.masterKeyChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final trustState = _trust?.state ?? ContactTrustState.identityUnavailable;
    final fingerprint = _fingerprint;
    final canConfirm = _canConfirm(trustState);
    return Scaffold(
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          semanticLabel: strings.authBackAction,
          onPressed: () => context.pop(),
          kind: AppButtonKind.ghost,
        ),
        title: Text(strings.safetyTitle),
      ),
      body: _busy && fingerprint == null
          ? AppStatePanel.loading(title: strings.safetyRefreshing)
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.x6),
              children: [
                _Notice(
                  key: ValueKey('safety-state-${trustState.name}'),
                  kind: trustState == ContactTrustState.verified
                      ? AppStatusKind.success
                      : canConfirm
                      ? AppStatusKind.warning
                      : AppStatusKind.danger,
                  message: _trustMessage(strings, trustState),
                ),
                const SizedBox(height: AppSpacing.x4),
                Text(strings.safetyInstructions),
                if (fingerprint != null) ...[
                  const SizedBox(height: AppSpacing.x6),
                  _SafetyValue(
                    label: strings.safetyEmojiLabel,
                    value: fingerprint.emojiCode,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  _SafetyValue(
                    label: strings.safetyNumberLabel,
                    value: fingerprint.numericCode,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  Semantics(
                    image: true,
                    label: strings.safetyQrLabel,
                    child: Center(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.x3),
                          child: QrImageView(
                            key: const ValueKey('safety-qr'),
                            data: fingerprint.qrValue,
                            size: 220,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                            semanticsLabel: strings.safetyQrLabel,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (canConfirm && fingerprint != null) ...[
                  const SizedBox(height: AppSpacing.x6),
                  AppCheckboxRow(
                    value: _confirmedOutOfBand,
                    label: strings.safetyOutOfBandCheck,
                    onChanged: _busy
                        ? null
                        : (value) =>
                              setState(() => _confirmedOutOfBand = value),
                  ),
                  AppButton(
                    key: const ValueKey('safety-confirm'),
                    label: strings.safetyConfirmAction,
                    onPressed: _busy || !_confirmedOutOfBand ? null : _confirm,
                    leading: AppIcons.security,
                  ),
                ],
                if (_failed) ...[
                  const SizedBox(height: AppSpacing.x6),
                  AppButton(
                    label: strings.safetyRetryAction,
                    onPressed: _busy ? null : _load,
                    kind: AppButtonKind.outline,
                    leading: AppIcons.retry,
                  ),
                ],
              ],
            ),
    );
  }

  String _trustMessage(AppLocalizations strings, ContactTrustState state) =>
      switch (state) {
        ContactTrustState.unverified => strings.safetyUnverifiedState,
        ContactTrustState.verified => strings.safetyVerifiedState,
        ContactTrustState.masterKeyChanged => strings.safetyMasterChangedState,
        ContactTrustState.invalidDevice => strings.safetyInvalidDeviceState,
        ContactTrustState.deviceLogFork => strings.safetyForkState,
        ContactTrustState.identityUnavailable =>
          strings.safetyIdentityUnavailableState,
      };
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onTap});

  final ContactProjection contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label:
          '${contact.presentationName}, ${contact.isVerified ? strings.contactsVerified : strings.contactsUnverified}',
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.x2),
        leading: ContactAvatar(
          username: contact.username,
          authenticatedSeed: contact.authenticatedAvatarSeed,
          semanticLabel: contact.presentationName,
        ),
        title: Text(contact.presentationName),
        subtitle: contact.presentationName == contact.username
            ? Text(strings.contactsUsernameFallback)
            : Text('@${contact.username}', textDirection: TextDirection.ltr),
        trailing: contact.isVerified
            ? AppIcon(
                AppIcons.security,
                decorative: false,
                semanticLabel: strings.contactsVerified,
                color: context.tokens.colors.success,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 56,
    leading: AppIcon(icon),
    title: Text(label),
    enabled: onTap != null,
    onTap: onTap,
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.kind, required this.message, super.key});

  final AppStatusKind kind;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: kind == AppStatusKind.danger,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.x3),
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceRaised,
        borderRadius: AppRadii.card,
        border: Border.all(color: context.tokens.colors.border),
      ),
      child: AppStatusBadge(kind: kind, label: message),
    ),
  );
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

class _SafetyValue extends StatelessWidget {
  const _SafetyValue({
    required this.label,
    required this.value,
    required this.textDirection,
  });

  final String label;
  final String value;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.tokens.colors.border),
        borderRadius: AppRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: context.tokens.typography.label),
            const SizedBox(height: AppSpacing.x2),
            SelectableText(
              value,
              textDirection: textDirection,
              textAlign: TextAlign.center,
              style: context.tokens.typography.section,
            ),
          ],
        ),
      ),
    ),
  );
}
