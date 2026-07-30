import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/features/messaging/application/conversation_use_cases.dart';
import 'package:communication_platform/features/messaging/infrastructure/drift_application_conversation_resolver.dart';
import 'package:communication_platform/features/messaging/infrastructure/pending_receipt_post_inbox_work.dart';
import 'package:communication_platform/features/pairwise/infrastructure/contact_selective_pairwise_claim_adapter.dart';
import 'package:communication_platform/features/pairwise/infrastructure/drift_pairwise_transport_store.dart';
import 'package:communication_platform/features/synchronization/application/durable_sync_engine.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/dio_sync_remote_port.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
import 'package:communication_platform/features/synchronization/infrastructure/pairwise_opaque_envelope_inspector.dart';
import 'package:communication_platform/features/synchronization/infrastructure/stale_device_refresh_adapter.dart';
import 'package:communication_platform/features/synchronization/infrastructure/sync_platform_adapters.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/pairwise_session_crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final durableSyncStoreProvider = FutureProvider<DurableSyncStore>((ref) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return DriftSyncStore(database);
});

/// Presentation observes this immutable Drift projection only. Socket and REST
/// callbacks are not exposed to widgets.
final syncProjectionProvider = StreamProvider<SyncProjection>((ref) async* {
  final store = await ref.watch(durableSyncStoreProvider.future);
  yield* store.watchProjection();
});

typedef PairwiseSyncScope = ({String userId, String deviceId});

/// Fully composed Android v1 durable sync engine. Envelope bytes reach the
/// native pairwise inspector before the Drift commit; unknown protocols fail
/// closed in the inspector.
final durableSyncEngineProvider =
    FutureProvider.family<DurableSyncEngine, PairwiseSyncScope>((
      ref,
      scope,
    ) async {
      final database = await ref.watch(localDatabaseProvider.future);
      final authentication = await ref.watch(
        peerAuthenticationServiceProvider.future,
      );
      final store = DriftSyncStore(database);
      final sender = await ref.watch(
        sendConversationEventsProvider((
          userId: scope.userId,
          deviceId: scope.deviceId,
        )).future,
      );
      final inspector = PairwiseOpaqueEnvelopeInspector(
        localDeviceId: scope.deviceId,
        store: DriftPairwiseTransportStore(database),
        liveDevices: ContactPairwiseLiveDeviceResolverAdapter(
          delegate: authentication,
          currentUserId: scope.userId,
        ),
        crypto: NativePairwiseSessionCrypto(ref.watch(pairwiseCryptoProvider)),
        applicationProtocol: ref.watch(applicationProtocolProvider),
        conversationResolver: DriftApplicationConversationResolver(
          database: database,
          protocol: ref.watch(applicationProtocolProvider),
        ),
        currentUserId: scope.userId,
        clock: ref.watch(timeSourceProvider),
      );
      return DurableSyncEngine(
        store: store,
        remote: DioSyncRemotePort(ref.watch(authenticatedRestClientProvider)),
        inspector: inspector,
        staleDeviceRefresh: ContactStaleDeviceRefreshAdapter(authentication),
        clock: ref.watch(timeSourceProvider),
        jitter: FullJitterSource(),
        postInboxCommitWork: PendingReceiptPostInboxWork(
          FlushPendingDeliveredReceipts(
            repository: await ref.watch(conversationRepositoryProvider.future),
            sender: sender,
            currentUserId: scope.userId,
          ),
        ),
      );
    });
