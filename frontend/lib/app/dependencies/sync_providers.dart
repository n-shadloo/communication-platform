import 'package:communication_platform/app/dependencies/contact_providers.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
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
      final inspector = PairwiseOpaqueEnvelopeInspector(
        localDeviceId: scope.deviceId,
        store: DriftPairwiseTransportStore(database),
        liveDevices: ContactPairwiseLiveDeviceResolverAdapter(
          delegate: authentication,
          currentUserId: scope.userId,
        ),
        crypto: NativePairwiseSessionCrypto(ref.watch(pairwiseCryptoProvider)),
        clock: ref.watch(timeSourceProvider),
      );
      return DurableSyncEngine(
        store: store,
        remote: DioSyncRemotePort(ref.watch(authenticatedRestClientProvider)),
        inspector: inspector,
        staleDeviceRefresh: ContactStaleDeviceRefreshAdapter(authentication),
        clock: ref.watch(timeSourceProvider),
        jitter: FullJitterSource(),
      );
    });
