import 'dart:async';
import 'dart:convert';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/devices/domain/device_enrollment_model.dart';
import 'package:communication_platform/features/devices/presentation/device_enrollment_controller.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final class DeviceEnrollmentPage extends ConsumerStatefulWidget {
  const DeviceEnrollmentPage({this.userId, super.key});

  final String? userId;

  @override
  ConsumerState<DeviceEnrollmentPage> createState() =>
      _DeviceEnrollmentPageState();
}

final class _DeviceEnrollmentPageState
    extends ConsumerState<DeviceEnrollmentPage> {
  final TextEditingController _recoverySecret = TextEditingController();
  bool _savedAcknowledged = false;
  bool _showConfirmation = false;
  bool _confirmedSafe = false;
  bool _sensitiveEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId =
          widget.userId ?? ref.read(authenticationControllerProvider).userId;
      if (mounted && userId != null) {
        unawaited(
          ref.read(deviceEnrollmentControllerProvider.notifier).start(userId),
        );
      }
    });
  }

  @override
  void dispose() {
    _recoverySecret
      ..clear()
      ..dispose();
    if (_sensitiveEnabled) {
      unawaited(const SensitiveScreenControl().setEnabled(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceEnrollmentControllerProvider);
    ref.listen(deviceEnrollmentControllerProvider, (previous, next) {
      final sensitive = switch (next.journal?.phase) {
        EnrollmentPhase.recoverySecret ||
        EnrollmentPhase.awaitingRecoverySecret ||
        EnrollmentPhase.restoringIdentity => true,
        _ => false,
      };
      if (sensitive != _sensitiveEnabled) {
        _sensitiveEnabled = sensitive;
        unawaited(const SensitiveScreenControl().setEnabled(sensitive));
      }
      if (next.journal?.recoverySecretDisplayed ?? false) {
        _savedAcknowledged = true;
      }
    });
    final l10n = AppLocalizations.of(context);
    final userId =
        widget.userId ?? ref.watch(authenticationControllerProvider).userId;
    if (userId == null) {
      return Scaffold(
        body: SafeArea(
          child: AppStatePanel.error(
            title: l10n.enrollmentSetupTitle,
            message: l10n.enrollmentInvalidVectorMessage,
          ),
        ),
      );
    }
    final journal = state.journal;
    if (journal == null) {
      return Scaffold(
        key: const ValueKey('device-enrollment-loading'),
        body: SafeArea(
          child: state.failure == null
              ? AppStatePanel.loading(
                  title: l10n.enrollmentSetupTitle,
                  message: l10n.enrollmentWithheldMessage,
                )
              : AppStatePanel.error(
                  title: l10n.enrollmentSetupTitle,
                  message: l10n.enrollmentGenericMessage,
                  actionLabel: l10n.retryAction,
                  onAction: () => ref
                      .read(deviceEnrollmentControllerProvider.notifier)
                      .retry(userId),
                ),
        ),
      );
    }

    final child = switch (journal.phase) {
      EnrollmentPhase.recoverySecret =>
        _showConfirmation
            ? _buildRecoveryConfirmation(l10n, userId, state.isBusy)
            : _buildRecoverySecret(l10n, journal, userId, state.isBusy),
      EnrollmentPhase.awaitingRecoverySecret => _buildRestore(
        l10n,
        journal,
        userId,
        state.isBusy,
      ),
      EnrollmentPhase.registrationOutcomeUnknown => _buildAmbiguous(
        l10n,
        userId,
        state.isBusy,
      ),
      EnrollmentPhase.securityNotice => _buildSecurityNotice(
        l10n,
        journal,
        userId,
        state.isBusy,
      ),
      EnrollmentPhase.blocked => _buildError(
        l10n,
        journal,
        userId,
        canRetry: false,
      ),
      _ when journal.message != null => _buildError(
        l10n,
        journal,
        userId,
        canRetry: true,
      ),
      _ => AppStatePanel.loading(
        key: const ValueKey('device-enrollment-progress'),
        title: l10n.enrollmentSetupTitle,
        message: l10n.enrollmentWithheldMessage,
      ),
    };

    return Scaffold(
      key: const ValueKey('device-enrollment-screen'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.x6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecoverySecret(
    AppLocalizations l10n,
    EnrollmentJournal journal,
    String userId,
    bool busy,
  ) {
    final secret = journal.identityPackage?.recoverySecret;
    if (secret == null) {
      return AppStatePanel.error(
        title: l10n.enrollmentRecoveryTitle,
        message: l10n.enrollmentInvalidVectorMessage,
      );
    }
    return _EnrollmentCard(
      key: const ValueKey('recovery-secret-step'),
      title: l10n.enrollmentRecoveryTitle,
      children: [
        Text(
          l10n.enrollmentRecoveryExplanation,
          style: context.tokens.typography.body,
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          l10n.enrollmentRecoverySeparate,
          style: context.tokens.typography.body.copyWith(
            color: context.tokens.colors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.x6),
        Semantics(
          label: l10n.enrollmentRecoveryTitle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.colors.surfaceRaised,
              borderRadius: AppRadii.compact,
              border: Border.all(color: context.tokens.colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: SelectableText(
                secret,
                key: const ValueKey('recovery-secret-value'),
                textAlign: TextAlign.center,
                style: context.tokens.typography.section.copyWith(
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        AppButton(
          key: const ValueKey('copy-recovery-secret'),
          label: l10n.enrollmentCopyAction,
          onPressed: busy ? null : () => _copySecret(secret, userId, l10n),
          kind: AppButtonKind.outline,
        ),
        AppCheckboxRow(
          key: const ValueKey('recovery-secret-saved'),
          value: _savedAcknowledged || journal.recoverySecretDisplayed,
          label: l10n.enrollmentSavedCheck,
          onChanged: busy
              ? null
              : (value) {
                  setState(() => _savedAcknowledged = value);
                  if (value) {
                    unawaited(
                      ref
                          .read(deviceEnrollmentControllerProvider.notifier)
                          .markRecoverySecretDisplayed(userId),
                    );
                  }
                },
        ),
        const SizedBox(height: AppSpacing.x3),
        AppButton(
          key: const ValueKey('recovery-secret-continue'),
          label: l10n.enrollmentContinueAction,
          onPressed:
              (_savedAcknowledged || journal.recoverySecretDisplayed) && !busy
              ? () => setState(() => _showConfirmation = true)
              : null,
        ),
      ],
    );
  }

  Widget _buildRecoveryConfirmation(
    AppLocalizations l10n,
    String userId,
    bool busy,
  ) => _EnrollmentCard(
    key: const ValueKey('recovery-confirmation-step'),
    title: l10n.enrollmentConfirmTitle,
    children: [
      AppCheckboxRow(
        key: const ValueKey('recovery-confirmed-safe'),
        value: _confirmedSafe,
        label: l10n.enrollmentConfirmCheck,
        onChanged: busy
            ? null
            : (value) => setState(() => _confirmedSafe = value),
      ),
      const SizedBox(height: AppSpacing.x4),
      AppButton(
        key: const ValueKey('recovery-confirm'),
        label: l10n.enrollmentConfirmAction,
        onPressed: _confirmedSafe && !busy
            ? () => ref
                  .read(deviceEnrollmentControllerProvider.notifier)
                  .confirmRecoverySecret(userId)
            : null,
      ),
      const SizedBox(height: AppSpacing.x2),
      AppButton(
        key: const ValueKey('recovery-back'),
        label: l10n.enrollmentBackToSecretAction,
        kind: AppButtonKind.ghost,
        onPressed: busy
            ? null
            : () => setState(() => _showConfirmation = false),
      ),
    ],
  );

  Widget _buildRestore(
    AppLocalizations l10n,
    EnrollmentJournal journal,
    String userId,
    bool busy,
  ) => _EnrollmentCard(
    key: const ValueKey('restore-identity-step'),
    title: l10n.enrollmentRestoreTitle,
    children: [
      Text(
        l10n.enrollmentRestoreExplanation,
        style: context.tokens.typography.body,
      ),
      const SizedBox(height: AppSpacing.x6),
      if (journal.message == EnrollmentMessage.wrongRecoverySecret) ...[
        _EnrollmentNotice(message: l10n.enrollmentWrongSecretMessage),
        const SizedBox(height: AppSpacing.x4),
      ],
      AppField(
        key: const ValueKey('recovery-secret-input'),
        label: l10n.enrollmentRecoverySecretLabel,
        controller: _recoverySecret,
        enabled: !busy,
        obscureText: true,
        textInputAction: TextInputAction.done,
        maxLength: 128,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => !busy ? _restore(userId) : null,
      ),
      const SizedBox(height: AppSpacing.x6),
      AppButton(
        key: const ValueKey('restore-identity-submit'),
        label: busy
            ? l10n.enrollmentRestoringAction
            : l10n.enrollmentRestoreAction,
        onPressed: !busy && _recoverySecret.text.trim().isNotEmpty
            ? () => _restore(userId)
            : null,
      ),
    ],
  );

  Widget _buildAmbiguous(AppLocalizations l10n, String userId, bool busy) =>
      _EnrollmentCard(
        key: const ValueKey('ambiguous-registration-step'),
        title: l10n.enrollmentAmbiguousTitle,
        children: [
          Text(
            l10n.enrollmentAmbiguousMessage,
            style: context.tokens.typography.body,
          ),
          const SizedBox(height: AppSpacing.x6),
          AppButton(
            key: const ValueKey('reconcile-registration'),
            label: l10n.enrollmentReconcileAction,
            onPressed: busy
                ? null
                : () => ref
                      .read(deviceEnrollmentControllerProvider.notifier)
                      .reconcile(userId),
          ),
        ],
      );

  Widget _buildSecurityNotice(
    AppLocalizations l10n,
    EnrollmentJournal journal,
    String userId,
    bool busy,
  ) => _EnrollmentCard(
    key: const ValueKey('mandatory-security-notice'),
    title: l10n.enrollmentSecurityTitle,
    children: [
      if (journal.flow == EnrollmentFlow.laterDevice) ...[
        Text(
          l10n.enrollmentIdentityRecoveredTitle,
          style: context.tokens.typography.section,
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          l10n.enrollmentNoHistoryMessage,
          style: context.tokens.typography.body,
        ),
        const SizedBox(height: AppSpacing.x6),
      ],
      Text(
        l10n.enrollmentProtectsHeading,
        style: context.tokens.typography.section,
      ),
      const SizedBox(height: AppSpacing.x2),
      Text(l10n.enrollmentProtectsBody, style: context.tokens.typography.body),
      const SizedBox(height: AppSpacing.x6),
      Text(
        l10n.enrollmentDoesNotProtectHeading,
        style: context.tokens.typography.section.copyWith(
          color: context.tokens.colors.danger,
        ),
      ),
      const SizedBox(height: AppSpacing.x2),
      Text(
        l10n.enrollmentDoesNotProtectBody,
        style: context.tokens.typography.body,
      ),
      const SizedBox(height: AppSpacing.x6),
      AppButton(
        key: const ValueKey('accept-security-notice'),
        label: l10n.enrollmentUnderstandAction,
        onPressed: busy ? null : () => _acceptNotice(userId),
      ),
    ],
  );

  Widget _buildError(
    AppLocalizations l10n,
    EnrollmentJournal journal,
    String userId, {
    required bool canRetry,
  }) => AppStatePanel.error(
    key: const ValueKey('device-enrollment-error'),
    title: l10n.enrollmentSetupTitle,
    message: _message(l10n, journal.message),
    actionLabel: canRetry ? l10n.retryAction : null,
    onAction: canRetry
        ? () => ref
              .read(deviceEnrollmentControllerProvider.notifier)
              .retry(userId)
        : null,
  );

  Future<void> _copySecret(
    String secret,
    String userId,
    AppLocalizations l10n,
  ) async {
    final copied = await const SensitiveScreenControl().copyText(secret);
    if (!mounted || !copied) {
      return;
    }
    setState(() => _savedAcknowledged = true);
    unawaited(
      ref
          .read(deviceEnrollmentControllerProvider.notifier)
          .markRecoverySecretDisplayed(userId),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.enrollmentCopiedMessage)));
  }

  Future<void> _restore(String userId) async {
    final normalized = _recoverySecret.text.trim();
    if (normalized.isEmpty) {
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(normalized));
    _recoverySecret.clear();
    await ref
        .read(deviceEnrollmentControllerProvider.notifier)
        .restoreIdentity(userId, bytes);
  }

  Future<void> _acceptNotice(String userId) async {
    final accepted = await ref
        .read(deviceEnrollmentControllerProvider.notifier)
        .acceptSecurityNotice(userId);
    if (!mounted || !accepted) {
      return;
    }
    ref.read(authenticationControllerProvider.notifier).secureSetupCompleted();
    context.go('/chats');
  }

  String _message(
    AppLocalizations l10n,
    EnrollmentMessage? message,
  ) => switch (message) {
    EnrollmentMessage.offline => l10n.authOfflineMessage,
    EnrollmentMessage.rateLimited => l10n.authRateLimitedMessage,
    EnrollmentMessage.deviceLimit => l10n.enrollmentDeviceLimitMessage,
    EnrollmentMessage.identityRequired =>
      l10n.enrollmentIdentityRequiredMessage,
    EnrollmentMessage.staleVersion => l10n.enrollmentStaleVersionMessage,
    EnrollmentMessage.invalidVector => l10n.enrollmentInvalidVectorMessage,
    EnrollmentMessage.wrongRecoverySecret => l10n.enrollmentWrongSecretMessage,
    EnrollmentMessage.backupMissing => l10n.enrollmentBackupMissingMessage,
    EnrollmentMessage.ambiguousRegistration => l10n.enrollmentAmbiguousMessage,
    EnrollmentMessage.logConflict => l10n.enrollmentLogConflictMessage,
    EnrollmentMessage.malformedResponse => l10n.authMalformedResponseMessage,
    EnrollmentMessage.storageUnavailable => l10n.authStorageUnavailableMessage,
    EnrollmentMessage.unsupportedProtocol => l10n.enrollmentUnsupportedMessage,
    EnrollmentMessage.generic || null => l10n.enrollmentGenericMessage,
  };
}

final class _EnrollmentCard extends StatelessWidget {
  const _EnrollmentCard({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.tokens.colors.surface,
      borderRadius: AppRadii.card,
      border: Border.all(color: context.tokens.colors.border),
      boxShadow: AppElevation.level1,
    ),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: context.tokens.typography.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.x6),
          ...children,
        ],
      ),
    ),
  );
}

final class _EnrollmentNotice extends StatelessWidget {
  const _EnrollmentNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.tokens.colors.surfaceRaised,
        borderRadius: AppRadii.compact,
        border: Border.all(color: context.tokens.colors.danger),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Text(
          message,
          style: context.tokens.typography.body.copyWith(
            color: context.tokens.colors.danger,
          ),
        ),
      ),
    ),
  );
}

final class SensitiveScreenControl {
  const SensitiveScreenControl();

  static const MethodChannel _channel = MethodChannel(
    'communication_platform/protected_storage',
  );

  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSensitiveScreen', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Widget tests and unsupported future platforms remain fail-closed at
      // the crypto boundary; they simply lack the Android screenshot control.
    } on PlatformException {
      // No error detail is surfaced across the privacy boundary.
    }
  }

  Future<bool> copyText(String text) async {
    try {
      await _channel.invokeMethod<void>('copySensitiveText', {
        'text': text,
        'clearAfterSeconds': 60,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
