import 'dart:async';

import 'package:communication_platform/app/config/deployment_disclosure.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/deployment_disclosure_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/devices/application/acknowledge_deployment_disclosure.dart';
import 'package:communication_platform/features/devices/presentation/security_notice_sections.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the deployment disclosure again, once, to somebody who accepted an
/// earlier version of it.
///
/// ## Why this exists at all
///
/// ADR-045 chose content-triggered re-acknowledgement over periodic
/// re-consent, and it was right to: repeated exposure to an unchanged warning
/// measurably destroys the attention paid to it, and the loss generalises to
/// warnings the reader has never seen, including this application's other
/// blocking security states. What ADR-045 did not build was the other half.
/// The revision moved at ADR-048, ADR-049 and ADR-051, and each time the only
/// thing that reached an existing recipient was a release-checklist step a
/// human had to remember to perform. Nothing recorded what anybody had
/// accepted, so nothing could tell that it had gone stale (ADR-052).
///
/// ## Why it is a full screen
///
/// The application posts ordinary message alerts and, when sustained delivery
/// is on, a permanent service notice. Habituation to routine notifications
/// transfers to warnings that resemble them, so a correction delivered as a
/// banner or a notification would arrive pre-ignored. A blocking screen the
/// application shows nowhere else is the surface least like the ones this
/// reader has learned to dismiss.
///
/// ## Why it wraps rather than routes
///
/// It sits above the router, so there is no route to deep-link past, no guard
/// ordering to get wrong, and no entry point — activity, deep link, or
/// notification tap — that reaches the application without passing it.
///
/// ## What it will not do
///
/// It never blocks a user who has not finished enrollment: enrollment shows the
/// statement itself and records it, and a gate in front of the login screen
/// would be a warning about a build shown to somebody with no account on it. It
/// never blocks when the record cannot be read, because an unreadable
/// preference row must not cost somebody their messages. And it dismisses on
/// the user's answer whether or not the write succeeds — a failed write costs
/// one more showing, which is the cheap direction.
final class DisclosureChangeGate extends ConsumerStatefulWidget {
  const DisclosureChangeGate({
    required this.child,
    this.sessionComposed = false,
    super.key,
  });

  final Widget child;

  /// Whether this composition installed the authentication stack at all.
  ///
  /// Passed down rather than discovered, because `authenticationControllerProvider`
  /// throws outright when its dependencies are absent, and a host that composes
  /// no session has nobody who could have accepted anything. A disclosure
  /// mechanism that can crash the application it is disclosing about would be a
  /// worse defect than the one it was built to fix.
  final bool sessionComposed;

  @override
  ConsumerState<DisclosureChangeGate> createState() =>
      _DisclosureChangeGateState();
}

class _DisclosureChangeGateState extends ConsumerState<DisclosureChangeGate> {
  bool _answered = false;

  @override
  Widget build(BuildContext context) {
    if (_answered || !widget.sessionComposed) {
      return widget.child;
    }
    final disclosure = ref.watch(appEnvironmentProvider).deploymentDisclosure;
    if (disclosure == null) {
      return widget.child;
    }
    // Enrollment is the first showing and writes the record itself. Until it
    // has completed there is nothing to re-present and nobody to re-present it
    // to.
    final access = ref.watch(authenticationControllerProvider).access;
    final enrolled =
        access == AuthenticationRouteAccess.fullScope ||
        access == AuthenticationRouteAccess.offlineFullScope;
    if (!enrolled) {
      return widget.child;
    }
    // Includes the loading and error cases: the application is never held
    // behind a preference row that has not resolved or cannot be read.
    final state =
        ref.watch(disclosureAcknowledgementStateProvider).value ??
        DisclosureAcknowledgementState.unknown;
    if (!state.outstanding) {
      return widget.child;
    }
    return DisclosureChangePage(
      disclosure: disclosure,
      acknowledgedRevision: state.acknowledgedRevision,
      onAcknowledged: () async {
        setState(() => _answered = true);
        final acknowledgement = await ref.read(
          disclosureAcknowledgementProvider.future,
        );
        await acknowledgement.accept(revision: disclosure.revision);
        ref.invalidate(disclosureAcknowledgementStateProvider);
      },
    );
  }
}

/// The screen the gate renders. Public so a widget test can pump it without a
/// database, and so it stays one layout rather than two.
final class DisclosureChangePage extends StatelessWidget {
  const DisclosureChangePage({
    required this.disclosure,
    required this.acknowledgedRevision,
    required this.onAcknowledged,
    super.key,
  });

  final DeploymentDisclosure disclosure;
  final int acknowledgedRevision;
  final FutureOr<void> Function() onAcknowledged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Nothing is marked for a reader with no record: marking every line marks
    // none of them, and 0 means this application does not know what they saw.
    final changed = acknowledgedRevision <= 0
        ? const <DisclosurePoint>{}
        : disclosure.changedSince(acknowledgedRevision);

    return Scaffold(
      key: const ValueKey('disclosure-change-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
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
                      Semantics(
                        header: true,
                        child: Text(
                          l10n.disclosureChangedTitle,
                          style: context.tokens.typography.title,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.x4),
                      Text(
                        l10n.disclosureChangedLead,
                        style: context.tokens.typography.body,
                      ),
                      const SizedBox(height: AppSpacing.x6),
                      SecurityNoticeSections(changedPoints: changed),
                      const SizedBox(height: AppSpacing.x6),
                      AppButton(
                        key: const ValueKey('accept-changed-disclosure'),
                        label: l10n.enrollmentUnderstandAction,
                        onPressed: () => onAcknowledged(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
