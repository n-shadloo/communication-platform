import 'package:communication_platform/app/config/deployment_disclosure.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/devices/application/acknowledge_deployment_disclosure.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_disclosure_acknowledgement_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The use case that reads and writes what the user has accepted.
///
/// A `FutureProvider` because opening protected storage is asynchronous and may
/// fail. Callers never see the failure: the use case answers
/// [DisclosureAcknowledgementState.unknown], which withholds the gate rather
/// than blocking the application on a preference row (ADR-052).
final disclosureAcknowledgementProvider =
    FutureProvider<AcknowledgeDeploymentDisclosure>((ref) async {
      final database = await ref.watch(localDatabaseProvider.future);
      return AcknowledgeDeploymentDisclosure(
        store: DriftDisclosureAcknowledgementStore(database),
      );
    });

/// Whether this build owes the person using it a second showing of its
/// statement, and which points moved.
///
/// Watched by the gate at the application root. It resolves to
/// [DisclosureAcknowledgementState.unknown] — nothing outstanding — for a build
/// that carries no disclosure at all, and for any host where protected storage
/// cannot be opened.
final disclosureAcknowledgementStateProvider =
    FutureProvider<DisclosureAcknowledgementState>((ref) async {
      final disclosure = ref.watch(appEnvironmentProvider).deploymentDisclosure;
      if (disclosure == null) {
        return DisclosureAcknowledgementState.unknown;
      }
      final acknowledgement = await ref.watch(
        disclosureAcknowledgementProvider.future,
      );
      return acknowledgement.state(currentRevision: disclosure.revision);
    });
