import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/local_storage_providers.dart';
import 'package:communication_platform/features/contacts/application/client_authentication_service.dart';
import 'package:communication_platform/features/contacts/application/contact_services.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/infrastructure/dio_contact_repository.dart';
import 'package:communication_platform/features/contacts/infrastructure/drift_contact_repository.dart';
import 'package:communication_platform/features/contacts/infrastructure/fake_profile_ports.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authenticatedRestClientProvider = Provider<DioRestClient>(
  (ref) => throw StateError('Authenticated REST client is not installed.'),
);

final contactRemoteProvider = Provider<DioContactRepository>(
  (ref) => DioContactRepository(ref.watch(authenticatedRestClientProvider)),
);

final contactLocalProvider = FutureProvider<ContactLocalPort>((ref) async {
  final database = await ref.watch(localDatabaseProvider.future);
  return DriftContactRepository(database);
});

final profileProtectionProvider = Provider<ProfileProtectionPort>((ref) {
  final environment = ref.watch(appEnvironmentProvider);
  return environment == AppEnvironment.development
      ? DevelopmentFakeProfileProtection()
      : const UnsupportedProfileProtection();
});

final profileKeyDistributionProvider = Provider<ProfileKeyDistributionPort>((
  ref,
) {
  final environment = ref.watch(appEnvironmentProvider);
  return environment == AppEnvironment.development
      ? DevelopmentFakeProfileKeyDistribution()
      : const UnsupportedProfileKeyDistribution();
});

final directoryServiceProvider = FutureProvider<DirectoryService>((ref) async {
  final local = await ref.watch(contactLocalProvider.future);
  return DirectoryService(
    remote: ref.watch(contactRemoteProvider),
    local: local,
  );
});

final peerAuthenticationServiceProvider =
    FutureProvider<ClientAuthenticationService>((ref) async {
      final local = await ref.watch(contactLocalProvider.future);
      return ClientAuthenticationService(
        remote: ref.watch(contactRemoteProvider),
        local: local,
        crypto: ref.watch(identityCryptoProvider),
      );
    });

final profileServiceProvider = FutureProvider<ProfileService>((ref) async {
  final local = await ref.watch(contactLocalProvider.future);
  final authentication = await ref.watch(
    peerAuthenticationServiceProvider.future,
  );
  return ProfileService(
    remote: ref.watch(contactRemoteProvider),
    local: local,
    authentication: authentication,
    protection: ref.watch(profileProtectionProvider),
    keyDistribution: ref.watch(profileKeyDistributionProvider),
  );
});

final contactListProvider = StreamProvider.autoDispose
    .family<List<ContactProjection>, String>((ref, ownUserId) async* {
      final local = await ref.watch(contactLocalProvider.future);
      yield* local.watchContacts(ownUserId: ownUserId);
    });

final contactProvider = StreamProvider.autoDispose
    .family<ContactProjection?, String>((ref, userId) async* {
      final local = await ref.watch(contactLocalProvider.future);
      yield* local.watchContact(userId);
    });
