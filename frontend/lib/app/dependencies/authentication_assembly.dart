import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/features/authentication/application/authentication_use_cases.dart';
import 'package:communication_platform/features/authentication/infrastructure/coordinated_authentication_session.dart';
import 'package:communication_platform/features/authentication/infrastructure/dio_account_authentication_repository.dart';
import 'package:communication_platform/features/authentication/infrastructure/secure_session_token_adapter.dart';
import 'package:communication_platform/features/devices/application/device_enrollment_coordinator.dart';
import 'package:communication_platform/features/devices/infrastructure/dio_device_enrollment_repository.dart';
import 'package:communication_platform/features/devices/infrastructure/drift_enrollment_journal_store.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/dio_token_endpoints.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/token_coordinator.dart';

final class AuthenticationAssembly {
  AuthenticationAssembly._({
    required this.useCases,
    required this.lifecycle,
    required this.enrollment,
    required this.restClient,
  });

  factory AuthenticationAssembly.create({
    required Uri serverOrigin,
    required SecureLocalStorageRuntime localStorage,
    required TimeSource timeSource,
    required EnrollmentCryptoPort enrollmentCrypto,
  }) {
    final lifecycle = AuthenticationLifecycleBus();
    final tokenStore = SecureSessionTokenAdapter(localStorage);
    final restClient = DioRestClient(serverOrigin: serverOrigin);
    final coordinator = TokenCoordinator(
      store: tokenStore,
      refreshExchange: DioRefreshTokenExchange(restClient),
      logoutExchange: DioLogoutTokenExchange(restClient),
      terminationHandler: LocalAuthenticationTerminationHandler(
        runtime: localStorage,
        lifecycle: lifecycle,
      ),
      timeSource: timeSource,
    );
    restClient.bindTokenCoordinator(coordinator);
    final session = CoordinatedAuthenticationSession(
      tokens: tokenStore,
      coordinator: coordinator,
      runtime: localStorage,
    );
    final enrollmentStore = DriftEnrollmentJournalStore(
      runtime: localStorage,
      tokens: tokenStore,
    );
    final repository = DioAccountAuthenticationRepository(restClient);
    final enrollment = DeviceEnrollmentCoordinator(
      repository: DioDeviceEnrollmentRepository(restClient),
      store: enrollmentStore,
      crypto: enrollmentCrypto,
      clock: timeSource,
    );
    return AuthenticationAssembly._(
      lifecycle: lifecycle,
      enrollment: enrollment,
      restClient: restClient,
      useCases: AuthenticationUseCases(
        register: RegisterAccount(
          repository,
          enrollmentMarker: enrollmentStore,
        ),
        login: LoginAccount(repository, session),
        restore: RestoreAccountSession(session),
        logout: LogoutAccount(session),
        lifecycle: lifecycle,
      ),
    );
  }

  final AuthenticationUseCases useCases;
  final AuthenticationLifecycleBus lifecycle;
  final DeviceEnrollmentCoordinator enrollment;
  final DioRestClient restClient;

  Future<void> close() => lifecycle.close();
}
