import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/core/application/ports/beta_mls_crypto_port.dart';
import 'package:communication_platform/features/groups/application/group_key_package_maintenance_service.dart';
import 'package:communication_platform/features/groups/application/group_mls_admission_service.dart';
import 'package:communication_platform/features/groups/application/group_outbound_dispatcher.dart';
import 'package:communication_platform/features/groups/application/group_use_cases.dart';
import 'package:communication_platform/features/groups/application/ports/group_key_package_ports.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/conversation_group_application_identity_adapter.dart';
import 'package:communication_platform/features/groups/infrastructure/development_in_memory_group_mls.dart';
import 'package:communication_platform/features/groups/infrastructure/dio_group_key_package_repository.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_key_package_maintenance_store.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_repository.dart';
import 'package:communication_platform/features/groups/infrastructure/native_beta_group_mls.dart';
import 'package:communication_platform/features/groups/infrastructure/pairwise_group_key_package_authentication.dart';
import 'package:communication_platform/features/groups/infrastructure/pairwise_group_live_device_adapter.dart';
import 'package:communication_platform/features/groups/infrastructure/pairwise_group_outbound_envelope_adapter.dart';
import 'package:communication_platform/features/groups/infrastructure/unsupported_group_mls.dart';
import 'package:communication_platform/features/pairwise/infrastructure/contact_selective_pairwise_claim_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GroupFeatureAvailability { developmentPreview, productionUnavailable }

final groupFeatureAvailabilityProvider = Provider<GroupFeatureAvailability>((
  ref,
) {
  final permit = GroupProductionGate.developmentPreviewPermit(
    ref.watch(appEnvironmentProvider),
  );
  return permit == null
      ? GroupFeatureAvailability.productionUnavailable
      : GroupFeatureAvailability.developmentPreview;
});

final groupMlsCryptoProvider = Provider<GroupMlsCryptoPort>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  final permit = GroupProductionGate.developmentPreviewPermit(environment);
  if (permit != null) {
    return DevelopmentInMemoryGroupMls.forDevelopmentPreview(permit);
  }
  if (environment == AppEnvironment.beta) {
    final crypto = ref.watch(cryptoCoreProvider);
    if (crypto is BetaMlsCryptoPort) {
      return NativeBetaGroupMls(crypto as BetaMlsCryptoPort);
    }
  }
  return const UnsupportedGroupMlsCrypto();
});

typedef GroupKeyPackageMaintenanceScope = ({String userId, String deviceId});

final groupKeyPackageRemoteProvider = Provider<GroupKeyPackageRemotePort>(
  (ref) =>
      DioGroupKeyPackageRepository(ref.watch(authenticatedRestClientProvider)),
);

final groupKeyPackageMaintenanceServiceProvider =
    FutureProvider.family<
      GroupKeyPackageMaintenanceService,
      GroupKeyPackageMaintenanceScope
    >((ref, scope) async {
      if (ref.watch(appEnvironmentProvider) != AppEnvironment.beta) {
        throw StateError(
          'PQ MLS KeyPackage maintenance is closed outside beta.',
        );
      }
      final database = await ref.watch(localDatabaseProvider.future);
      final peerAuthentication = await ref.watch(
        peerAuthenticationServiceProvider.future,
      );
      return GroupKeyPackageMaintenanceService(
        remote: ref.watch(groupKeyPackageRemoteProvider),
        authentication: PairwiseGroupKeyPackageAuthentication(
          ContactSelectivePairwiseClaimAdapter(
            delegate: peerAuthentication,
            currentUserId: scope.userId,
          ),
        ),
        crypto: ref.watch(groupMlsCryptoProvider),
        store: DriftGroupKeyPackageMaintenanceStore(database),
        clock: ref.watch(timeSourceProvider),
      );
    });

final groupRepositoryProvider = FutureProvider<GroupRepositoryPort>((
  ref,
) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return DriftGroupRepository(database);
});

final fullyComposedGroupMlsCryptoProvider = FutureProvider<GroupMlsCryptoPort>((
  ref,
) async {
  final fallback = ref.watch(groupMlsCryptoProvider);
  if (ref.watch(appEnvironmentProvider) != AppEnvironment.beta) {
    return fallback;
  }
  final core = ref.watch(cryptoCoreProvider);
  if (core is! BetaMlsCryptoPort) return fallback;
  final betaCore = core as BetaMlsCryptoPort;
  final database = await ref.watch(localDatabaseProvider.future);
  final peerAuthentication = await ref.watch(
    peerAuthenticationServiceProvider.future,
  );
  final conversationRepository = await ref.watch(
    conversationRepositoryProvider.future,
  );
  return NativeBetaGroupMls(
    betaCore,
    admission: GroupMlsAdmissionService(
      remote: ref.watch(groupKeyPackageRemoteProvider),
      authenticationForCurrentUser: (currentUserId) =>
          PairwiseGroupKeyPackageAuthentication(
            ContactSelectivePairwiseClaimAdapter(
              delegate: peerAuthentication,
              currentUserId: currentUserId,
            ),
          ),
      store: DriftGroupKeyPackageMaintenanceStore(database),
      liveDevicesForCurrentUser: (currentUserId) =>
          PairwiseGroupLiveDeviceAdapter(
            ContactPairwiseLiveDeviceResolverAdapter(
              delegate: peerAuthentication,
              currentUserId: currentUserId,
            ),
          ),
      clock: ref.watch(timeSourceProvider),
    ),
    applicationProtocol: ref.watch(applicationProtocolProvider),
    applicationIdentity: ConversationGroupApplicationIdentityAdapter(
      conversationRepository,
    ),
    transcript: DriftGroupRepository(database),
  );
});

final groupOutboundDispatcherProvider =
    FutureProvider.family<
      GroupOutboundDispatcher,
      GroupKeyPackageMaintenanceScope
    >((ref, scope) async {
      final repository = await ref.watch(groupRepositoryProvider.future);
      final fanout = await ref.watch(
        pairwiseFanoutCoordinatorProvider((
          userId: scope.userId,
          deviceId: scope.deviceId,
        )).future,
      );
      return GroupOutboundDispatcher(
        repository: repository,
        envelopes: PairwiseGroupOutboundEnvelopeAdapter(fanout),
      );
    });

final groupUseCasesProvider = FutureProvider<GroupUseCases>((ref) async {
  final repository = await ref.watch(groupRepositoryProvider.future);
  final preview =
      ref.watch(groupFeatureAvailabilityProvider) ==
      GroupFeatureAvailability.developmentPreview;
  final crypto = await ref.watch(fullyComposedGroupMlsCryptoProvider.future);
  final clock = ref.watch(timeSourceProvider);
  return GroupUseCases(
    create: CreateGroup(
      repository: repository,
      crypto: crypto,
      clock: clock,
      developmentPreviewOnly: preview,
    ),
    mutate: MutateGroup(
      repository: repository,
      crypto: crypto,
      clock: clock,
      developmentPreviewOnly: preview,
    ),
    sendMessage: SendGroupMessage(
      repository: repository,
      crypto: crypto,
      clock: clock,
      developmentPreviewOnly: preview,
    ),
    acceptWelcome: AcceptGroupWelcome(repository: repository, crypto: crypto),
    applyIncomingMessage: ApplyIncomingGroupMessage(
      repository: repository,
      crypto: crypto,
    ),
  );
});

final groupProvider = StreamProvider.autoDispose.family<GroupState?, String>((
  ref,
  groupId,
) async* {
  final repository = await ref.watch(groupRepositoryProvider.future);
  yield* repository.watchGroup(groupId);
});

final groupMessagesProvider = StreamProvider.autoDispose
    .family<List<GroupMessage>, String>((ref, groupId) async* {
      final repository = await ref.watch(groupRepositoryProvider.future);
      yield* repository.watchMessages(groupId);
    });
