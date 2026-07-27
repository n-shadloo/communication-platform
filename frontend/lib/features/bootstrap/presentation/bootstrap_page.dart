import 'dart:async';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/bootstrap/application/bootstrap_flow.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

enum BootstrapDestination { login, application }

final class BootstrapNavigation {
  const BootstrapNavigation({
    required this.destination,
    this.offline = false,
    this.rememberedUsername,
  });

  final BootstrapDestination destination;
  final bool offline;
  final String? rememberedUsername;
}

/// Splash and blocking connection gate. Progress is state-based; it never invents a
/// percentage, delay, or remote connectivity probe.
class BootstrapPage extends StatefulWidget {
  const BootstrapPage({
    required this.flow,
    required this.platform,
    required this.isProduction,
    required this.onResolved,
    super.key,
  });

  final BootstrapFlow flow;
  final BootstrapPlatform platform;
  final bool isProduction;
  final ValueChanged<BootstrapNavigation> onResolved;

  @override
  State<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends State<BootstrapPage> {
  BootstrapState _state = const LoadingBootstrapConfiguration();
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_run);
  }

  void _run() {
    final attempt = ++_attempt;
    unawaited(
      widget.flow.run((state) {
        if (!mounted || attempt != _attempt) {
          return;
        }
        setState(() => _state = state);
        _resolveIfReady(state, attempt);
      }),
    );
  }

  void _resolveIfReady(BootstrapState state, int attempt) {
    final navigation = switch (state) {
      BootstrapLoginRequired(:final rememberedUsername) => BootstrapNavigation(
        destination: BootstrapDestination.login,
        rememberedUsername: rememberedUsername,
      ),
      BootstrapApplicationReady(:final offline) => BootstrapNavigation(
        destination: BootstrapDestination.application,
        offline: offline,
      ),
      _ => null,
    };
    if (navigation == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && attempt == _attempt) {
        widget.onResolved(navigation);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = _state;
    final connection = state is BootstrapConnectionBlocked ? state : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isProduction)
              Semantics(
                container: true,
                liveRegion: true,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.x3),
                    child: Text(
                      l10n.developmentConfiguration,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.x6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Semantics(
                      key: const ValueKey('bootstrap-status'),
                      container: true,
                      liveRegion: true,
                      explicitChildNodes: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: context.tokens.colors.accentSoft,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(
                                dimension: 72,
                                child: Center(
                                  child: Text(
                                    'CP',
                                    style: context.tokens.typography.section,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.x4),
                          Text(
                            l10n.appTitle,
                            style: context.tokens.typography.title,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppSpacing.x3),
                          Text(
                            _title(l10n, state),
                            key: const ValueKey('bootstrap-status-title'),
                            style: context.tokens.typography.section,
                            textAlign: TextAlign.center,
                          ),
                          if (connection != null) ...[
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              _message(l10n, connection),
                              key: const ValueKey('bootstrap-status-message'),
                              style: context.tokens.typography.body.copyWith(
                                color: context.tokens.colors.textMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (connection.retryAllowed) ...[
                              const SizedBox(height: AppSpacing.x6),
                              AppButton(
                                key: const ValueKey('bootstrap-retry'),
                                label: l10n.retryAction,
                                onPressed: _run,
                                kind: AppButtonKind.outline,
                                autofocus: true,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(AppLocalizations l10n, BootstrapState state) => switch (state) {
    LoadingBootstrapConfiguration() => l10n.bootstrapLoadingConfiguration,
    CheckingProtectedStorage() => l10n.bootstrapCheckingStorage,
    DiscoveringLocalBootstrapState() => l10n.bootstrapDiscoveringIdentity,
    ValidatingBootstrapTrust() => l10n.bootstrapValidatingTrust,
    CheckingBackendHealth() => l10n.bootstrapCheckingServer,
    BootstrapConnectionBlocked(:final issue) => switch (issue) {
      BootstrapConnectionIssue.notProvisioned => l10n.notProvisionedTitle,
      BootstrapConnectionIssue.protectedStorageUnavailable =>
        l10n.protectedStorageUnavailableTitle,
      BootstrapConnectionIssue.trustFailure => l10n.trustFailureTitle,
      BootstrapConnectionIssue.serverUnreachable => l10n.serverUnreachableTitle,
    },
    BootstrapLoginRequired() ||
    BootstrapApplicationReady() => l10n.bootstrapReady,
  };

  String _message(AppLocalizations l10n, BootstrapConnectionBlocked state) =>
      switch (state.issue) {
        BootstrapConnectionIssue.notProvisioned => l10n.notProvisionedMessage,
        BootstrapConnectionIssue.protectedStorageUnavailable =>
          l10n.protectedStorageUnavailableMessage,
        BootstrapConnectionIssue.trustFailure =>
          widget.platform == BootstrapPlatform.web
              ? l10n.webTrustFailureMessage
              : l10n.androidTrustFailureMessage,
        BootstrapConnectionIssue.serverUnreachable =>
          l10n.serverUnreachableMessage,
      };
}

/// Piece 04 owns the guarded destination, not the login form implemented later.
class LoginRouteBoundaryPage extends StatelessWidget {
  const LoginRouteBoundaryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('login-route-boundary'),
    body: SafeArea(
      child: Center(
        child: Text(
          AppLocalizations.of(context).loginDestination,
          style: context.tokens.typography.title,
        ),
      ),
    ),
  );
}
