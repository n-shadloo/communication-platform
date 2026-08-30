import 'package:communication_platform/app/dependencies/group_providers.dart';
import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/app/design_system/app_tokens.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GroupProductionGatePage extends ConsumerWidget {
  const GroupProductionGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    // Two builds reach this page for two different reasons and it says which.
    // Production has no group stack at all; the private experimental build has
    // one and is holding it closed until the packaged core has been observed
    // running on hardware (ADR-055). Telling a recipient of the second that
    // "production groups are not available" would be answering a question they
    // did not ask.
    final withheld =
        ref.watch(groupFeatureAvailabilityProvider) ==
        GroupFeatureAvailability.privateExperimentalWithheld;
    return Scaffold(
      key: withheld
          ? const ValueKey('group-experimental-withheld-gate')
          : const ValueKey('group-production-gate'),
      appBar: AppBar(title: Text(strings.groupInfoTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppStatePanel.error(
              title: withheld
                  ? strings.groupExperimentalWithheldTitle
                  : strings.groupProductionUnavailableTitle,
              message: withheld
                  ? strings.groupExperimentalWithheldMessage
                  : strings.groupProductionUnavailableMessage,
            ),
          ),
        ),
      ),
    );
  }
}
