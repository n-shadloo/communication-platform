import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/messaging/application/conversation_use_cases.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_conversation_domain_repository.dart';
import 'package:communication_platform/features/messaging/infrastructure/memory_volatile_conversation_state.dart';
import 'package:communication_platform/features/messaging/infrastructure/pairwise_application_fanout_adapter.dart';
import 'package:communication_platform/features/pairwise/application/pairwise_fanout_coordinator.dart';
import 'package:communication_platform/features/pairwise/infrastructure/contact_selective_pairwise_claim_adapter.dart';
import 'package:communication_platform/features/pairwise/infrastructure/drift_pairwise_transport_store.dart';
import 'package:communication_platform/features/pairwise/infrastructure/native_pairwise_outbound_preparation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef MessagingScope = ({String userId, String deviceId});
typedef ConversationMessagesRequest = ({
  String currentUserId,
  String conversationId,
});

final conversationRepositoryProvider =
    FutureProvider<ConversationRepositoryPort>((ref) async {
      final database = await ref.watch(localDatabaseProvider.future);
      return DriftConversationDomainRepository(database);
    });

final conversationSummariesProvider = StreamProvider.autoDispose
    .family<List<ConversationSummary>, String>((ref, currentUserId) async* {
      final repository = await ref.watch(conversationRepositoryProvider.future);
      yield* repository.watchConversations(currentUserId);
    });

final conversationMessagesProvider = StreamProvider.autoDispose
    .family<List<ConversationMessage>, ConversationMessagesRequest>((
      ref,
      request,
    ) async* {
      final repository = await ref.watch(conversationRepositoryProvider.future);
      yield* repository.watchMessages(
        currentUserId: request.currentUserId,
        conversationId: request.conversationId,
      );
    });

final volatileConversationStateProvider =
    Provider<VolatileConversationStatePort>((ref) {
      final state = MemoryVolatileConversationState();
      ref.onDispose(state.dispose);
      return state;
    });

final typingProjectionsProvider = StreamProvider.autoDispose
    .family<List<TypingProjection>, String>((ref, conversationId) {
      return ref
          .watch(volatileConversationStateProvider)
          .watchTyping(conversationId);
    });

final presenceProjectionProvider = StreamProvider.autoDispose
    .family<PresenceProjection, String>((ref, userId) {
      return ref.watch(volatileConversationStateProvider).watchPresence(userId);
    });

final sendConversationEventsProvider =
    FutureProvider.family<SendConversationEvents, MessagingScope>((
      ref,
      scope,
    ) async {
      final database = await ref.watch(localDatabaseProvider.future);
      final authentication = await ref.watch(
        peerAuthenticationServiceProvider.future,
      );
      final liveDevices = ContactPairwiseLiveDeviceResolverAdapter(
        delegate: authentication,
        currentUserId: scope.userId,
      );
      return SendConversationEvents(
        repository: DriftConversationDomainRepository(database),
        protocol: ref.watch(applicationProtocolProvider),
        fanout: PairwiseApplicationFanoutAdapter(
          PairwiseFanoutCoordinator(
            store: DriftPairwiseTransportStore(database),
            liveDevices: liveDevices,
            claims: ContactSelectivePairwiseClaimAdapter(
              delegate: authentication,
              currentUserId: scope.userId,
            ),
            crypto: NativePairwiseOutboundPreparation(
              ref.watch(pairwiseSessionCryptoProvider),
            ),
            clock: ref.watch(timeSourceProvider),
          ),
        ),
        clock: ref.watch(timeSourceProvider),
      );
    });

final manageLocalConversationStateProvider =
    FutureProvider<ManageLocalConversationState>((ref) async {
      final repository = await ref.watch(conversationRepositoryProvider.future);
      return ManageLocalConversationState(repository);
    });
