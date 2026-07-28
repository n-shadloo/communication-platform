import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/application/ports/authentication_ports.dart';
import 'package:communication_platform/features/authentication/domain/authentication_model.dart';
import 'package:communication_platform/features/authentication/infrastructure/coordinated_authentication_session.dart';
import 'package:communication_platform/features/authentication/infrastructure/secure_session_token_adapter.dart';
import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/token_coordinator.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('secure session token adapter', () {
    late TestStorageHarness harness;

    setUp(() {
      harness = TestStorageHarness();
    });

    tearDown(() async {
      await harness.runtime.close();
    });

    test(
      'persists refresh material but keeps access token in memory',
      () async {
        final adapter = SecureSessionTokenAdapter(harness.runtime);
        await adapter.replace(fullTokens());
        final database =
            (await harness.runtime.open() as Success<LocalDatabase>).value;
        final row = await database.select(database.accountSessions).getSingle();
        final metadata = utf8.decode(row.tokenMetadataCiphertext);

        expect(metadata, contains('refresh-secret'));
        expect(metadata, isNot(contains('access-secret')));

        final restarted = SecureSessionTokenAdapter(harness.runtime);
        final restored = await restarted.read();
        expect(restored?.accessToken.value, isEmpty);
        expect(restored?.refreshToken, 'refresh-secret');
        expect(restored?.userId, userId);
        expect(restored?.deviceId, deviceId);
      },
    );

    test(
      'register-scope access is memory-only and has no durable session row',
      () async {
        final adapter = SecureSessionTokenAdapter(harness.runtime);
        await adapter.replace(
          SessionTokens(
            accessToken: AccessToken(
              value: 'register-secret',
              expiresAt: DateTime.utc(2026, 7, 28, 13),
              scope: SessionScope.register,
            ),
            userId: userId,
            username: 'alice',
          ),
        );
        final database =
            (await harness.runtime.open() as Success<LocalDatabase>).value;

        expect((await adapter.read())?.accessToken.value, 'register-secret');
        expect(
          await database.select(database.accountSessions).getSingleOrNull(),
          isNull,
        );
        expect(await SecureSessionTokenAdapter(harness.runtime).read(), isNull);
      },
    );

    test(
      'offline restore is allowed only with a usable local identity',
      () async {
        final adapter = SecureSessionTokenAdapter(harness.runtime);
        await adapter.replace(fullTokens());
        adapter.clearMemory();
        final database =
            (await harness.runtime.open() as Success<LocalDatabase>).value;
        await database
            .into(database.accountIdentities)
            .insert(
              AccountIdentitiesCompanion.insert(
                verifiedPublicStateCiphertext: Uint8List.fromList([1, 2, 3]),
                recoveryStatus: 0,
              ),
            );
        final lifecycle = AuthenticationLifecycleBus();
        final coordinator = TokenCoordinator(
          store: adapter,
          refreshExchange: const FixedRefreshExchange(
            Result.failure(TransportFailure(TransportFailureKind.offline)),
          ),
          terminationHandler: LocalAuthenticationTerminationHandler(
            runtime: harness.runtime,
            lifecycle: lifecycle,
          ),
          timeSource: const FixedTimeSource(),
        );
        final session = CoordinatedAuthenticationSession(
          tokens: adapter,
          coordinator: coordinator,
          runtime: harness.runtime,
        );

        final result = await session.restore();

        expect(
          (result as Success<AccountSessionBoundary>).value.offline,
          isTrue,
        );
        expect(result.value.securitySetupComplete, isFalse);
        expect(harness.cleanup.erased, isFalse);
        await lifecycle.close();
      },
    );

    test(
      'revoked refresh wipes local artifacts and emits revocation',
      () async {
        final adapter = SecureSessionTokenAdapter(harness.runtime);
        await adapter.replace(fullTokens());
        adapter.clearMemory();
        final lifecycle = AuthenticationLifecycleBus();
        final termination = expectLater(
          lifecycle.terminations,
          emits(AuthenticationTermination.revoked),
        );
        final coordinator = TokenCoordinator(
          store: adapter,
          refreshExchange: const FixedRefreshExchange(
            Result.failure(BackendFailure(BackendFailureCode.tokenRevoked)),
          ),
          terminationHandler: LocalAuthenticationTerminationHandler(
            runtime: harness.runtime,
            lifecycle: lifecycle,
          ),
          timeSource: const FixedTimeSource(),
        );
        final session = CoordinatedAuthenticationSession(
          tokens: adapter,
          coordinator: coordinator,
          runtime: harness.runtime,
        );

        final result = await session.restore();

        expect(result, isA<FailureResult<AccountSessionBoundary>>());
        await termination;
        expect(harness.protectedStorage.destroyed, isTrue);
        expect(harness.cleanup.erased, isTrue);
        await lifecycle.close();
      },
    );
  });
}

const userId = '6f0c2f5e-8a41-4c9e-9a34-1f3d8f2b7c10';
const deviceId = '9f1c6a2e-3b7d-4e0f-8c15-2a77d4b9e611';

SessionTokens fullTokens() => SessionTokens(
  accessToken: AccessToken(
    value: 'access-secret',
    expiresAt: DateTime.utc(2026, 7, 28, 11),
    scope: SessionScope.full,
  ),
  refreshToken: 'refresh-secret',
  refreshExpiresAt: DateTime.utc(2026, 8),
  userId: userId,
  deviceId: deviceId,
  username: 'alice',
);

final class TestStorageHarness {
  TestStorageHarness() {
    protectedStorage = FakeProtectedStorage();
    cleanup = FakeCleanup();
    runtime = SecureLocalStorageRuntime(
      protectedStorage: protectedStorage,
      cleanup: cleanup,
      executorFactory: (_) => NativeDatabase.memory(),
    );
  }

  late final FakeProtectedStorage protectedStorage;
  late final FakeCleanup cleanup;
  late final SecureLocalStorageRuntime runtime;
}

final class FakeProtectedStorage implements PlatformProtectedStoragePort {
  bool destroyed = false;

  @override
  Future<void> destroyWrappingKey() async {
    destroyed = true;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async =>
      PlatformStorageUnlock(
        status: PlatformStorageKeyStatus.ready,
        protection: PlatformStorageProtection.software,
        databaseKey: Uint8List(32),
      );
}

final class FakeCleanup implements LocalArtifactCleanupPort {
  bool erased = false;

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async =>
      const CleanupReport(removedEntries: 0, hasMore: false);

  @override
  Future<void> clearVolatilePlaintext() async {}

  @override
  Future<void> erasePersistentArtifacts() async {
    erased = true;
  }
}

final class FixedRefreshExchange implements RefreshTokenExchange {
  const FixedRefreshExchange(this.result);

  final Result<SessionTokens> result;

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async => result;
}

final class FixedTimeSource implements TimeSource {
  const FixedTimeSource();

  @override
  DateTime now() => DateTime.utc(2026, 7, 28, 12);
}
