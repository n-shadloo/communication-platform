import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/groups/application/group_use_cases.dart';
import 'package:communication_platform/features/groups/application/ports/group_ports.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/development_in_memory_group_mls.dart';
import 'package:communication_platform/features/groups/infrastructure/drift_group_repository.dart';
import 'package:communication_platform/features/groups/infrastructure/unsupported_group_mls.dart';
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
  final permit = GroupProductionGate.developmentPreviewPermit(
    ref.watch(appEnvironmentProvider),
  );
  return permit == null
      ? const UnsupportedGroupMlsCrypto()
      : DevelopmentInMemoryGroupMls.forDevelopmentPreview(permit);
});

final groupRepositoryProvider = FutureProvider<GroupRepositoryPort>((
  ref,
) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return DriftGroupRepository(database);
});

final groupUseCasesProvider = FutureProvider<GroupUseCases>((ref) async {
  final repository = await ref.watch(groupRepositoryProvider.future);
  final preview =
      ref.watch(groupFeatureAvailabilityProvider) ==
      GroupFeatureAvailability.developmentPreview;
  final crypto = ref.watch(groupMlsCryptoProvider);
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
