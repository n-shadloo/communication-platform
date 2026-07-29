import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sync_store.dart';
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
