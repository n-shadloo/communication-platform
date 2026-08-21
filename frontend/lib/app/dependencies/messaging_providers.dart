import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/infrastructure/device_log_gossip_coordinator.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_linked_device_repository.dart';
import 'package:communication_platform/features/messaging/application/conversation_use_cases.dart';
import 'package:communication_platform/features/messaging/application/ports/conversation_ports.dart';
import 'package:communication_platform/features/messaging/domain/conversation_model.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_conversation_domain_repository.dart';
import 'package:communication_platform/features/messaging/infrastructure/memory_volatile_conversation_state.dart';
import 'package:communication_platform/features/messaging/infrastructure/pairwise_application_fanout_adapter.dart';
import 'package:communication_platform/features/messaging/presentation/visible_conversation.dart';
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
typedef ConversationIdentityRequest = ({
  String currentUserId,
  String? peerUserId,
  bool savedMessages,
});

final currentMessagingDeviceIdProvider = FutureProvider<String>((ref) async {
  final local = await ref.watch(contactLocalProvider.future);
  final result = await local.readLocalIdentity();
  return switch (result) {
    Success(:final value) => value.deviceId,
    FailureResult(:final failure) => throw StateError(
      'Messaging identity is unavailable: ${failure.runtimeType}',
    ),
  };
});

final conversationIdentityProvider = FutureProvider.autoDispose
    .family<String, ConversationIdentityRequest>((ref, request) async {
      final protocol = ref.watch(applicationProtocolProvider);
      final result = request.savedMessages
          ? await protocol.deriveSavedConversationId(
              protocolUuidBytes(request.currentUserId),
            )
          : await protocol.deriveDirectConversationId(
              firstUserId: protocolUuidBytes(request.currentUserId),
              secondUserId: protocolUuidBytes(request.peerUserId!),
            );
      return switch (result) {
        Success(:final value) => protocolBytesToHex(value),
        FailureResult(:final failure) => throw StateError(
          'Conversation identity is unavailable: ${failure.runtimeType}',
        ),
      };
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

/// Which conversation the user is looking at, owned for the life of the
/// application because it is read by something that is not a screen: the alert
/// path has to know what is already on screen in order not to announce it.
final visibleConversationProvider = Provider<VisibleConversationRegistry>((
  ref,
) {
  final registry = VisibleConversationRegistry();
  ref.onDispose(registry.dispose);
  return registry;
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

final pairwiseFanoutCoordinatorProvider =
    FutureProvider.family<PairwiseFanoutCoordinator, MessagingScope>((
      ref,
      scope,
    ) async {
      final database = await ref.watch(localDatabaseProvider.future);
      final authentication = await ref.watch(
        peerAuthenticationServiceProvider.future,
      );
      return PairwiseFanoutCoordinator(
        store: DriftPairwiseTransportStore(database),
        liveDevices: ContactPairwiseLiveDeviceResolverAdapter(
          delegate: authentication,
          currentUserId: scope.userId,
        ),
        claims: ContactSelectivePairwiseClaimAdapter(
          delegate: authentication,
          currentUserId: scope.userId,
        ),
        crypto: NativePairwiseOutboundPreparation(
          ref.watch(pairwiseSessionCryptoProvider),
        ),
        clock: ref.watch(timeSourceProvider),
      );
    });

final sendConversationEventsProvider =
    FutureProvider.family<SendConversationEvents, MessagingScope>((
      ref,
      scope,
    ) async {
      final database = await ref.watch(localDatabaseProvider.future);
      final fanout = await ref.watch(
        pairwiseFanoutCoordinatorProvider(scope).future,
      );
      final gossip = DeviceLogGossipCoordinator(
        database: database,
        local: DriftLinkedDeviceRepository(database),
        protocol: ref.watch(applicationProtocolProvider),
        controlCrypto: ref.watch(deviceControlCryptoProvider),
        fanout: fanout,
        currentUserId: scope.userId,
        currentDeviceId: scope.deviceId,
      );
      return SendConversationEvents(
        repository: DriftConversationDomainRepository(database),
        protocol: ref.watch(applicationProtocolProvider),
        fanout: PairwiseApplicationFanoutAdapter(
          fanout,
          afterSuccessfulQueue: (peerUserId) async {
            await gossip.queueForUser(peerUserId);
          },
        ),
        clock: ref.watch(timeSourceProvider),
      );
    });

final manageLocalConversationStateProvider =
    FutureProvider<ManageLocalConversationState>((ref) async {
      final repository = await ref.watch(conversationRepositoryProvider.future);
      return ManageLocalConversationState(repository);
    });
