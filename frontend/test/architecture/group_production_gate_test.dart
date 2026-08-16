import 'dart:io';
import 'dart:typed_data';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/group_providers.dart';
import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/infrastructure/unsupported_group_mls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PQ MLS production gate is a closed compile-time constant', () {
    expect(
      GroupProductionGate.releaseAssertion.productionTransportEnabled,
      isFalse,
    );
    final source = File(
      'lib/app/config/group_production_gate.dart',
    ).readAsStringSync();
    expect(source, contains('productionTransportEnabled: false'));
    expect(source, contains('assert('));
    expect(source, isNot(contains('bool.fromEnvironment')));
    expect(source, isNot(contains('String.fromEnvironment')));
    expect(
      File('lib/main_production.dart').readAsStringSync(),
      contains('GroupProductionGate.releaseAssertion'),
    );
  });

  test('production provider cannot install the development MLS fake', () {
    final container = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(AppEnvironment.production),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(groupFeatureAvailabilityProvider),
      GroupFeatureAvailability.productionUnavailable,
    );
    expect(
      container.read(groupMlsCryptoProvider),
      isA<UnsupportedGroupMlsCrypto>(),
    );
  });

  test(
    'production composes the unsupported adapter into the consumed port',
    () {
      // `groupUseCasesProvider` and the durable sync engine read the fully
      // composed provider, not the bare one asserted above.
      final container = ProviderContainer(
        overrides: [
          appEnvironmentProvider.overrideWithValue(AppEnvironment.production),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(fullyComposedGroupMlsCryptoProvider.future),
        completion(isA<UnsupportedGroupMlsCrypto>()),
      );
    },
  );

  test('production has no KeyPackage maintenance path', () {
    final container = ProviderContainer(
      overrides: [
        appEnvironmentProvider.overrideWithValue(AppEnvironment.production),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(
        groupKeyPackageMaintenanceServiceProvider((
          userId: '11111111-1111-4111-8111-111111111111',
          deviceId: '22222222-2222-4222-8222-222222222222',
        )).future,
      ),
      throwsStateError,
    );
  });

  test('the unsupported adapter fails closed on every port method', () async {
    const crypto = UnsupportedGroupMlsCrypto();
    const ownerId = '11111111-1111-4111-8111-111111111111';
    const ownerDeviceId = '22222222-2222-4222-8222-222222222222';
    final empty = Uint8List(0);
    final owner = GroupMember(
      userId: ownerId,
      displayName: 'owner',
      role: GroupRole.owner,
      deviceIds: const [ownerDeviceId],
    );
    final state = GroupState(
      groupId: '00' * 32,
      metadata: const GroupMetadata(name: 'closed'),
      invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
      historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
      members: [owner],
      controlRevision: 1,
      controlStateHash: '11' * 32,
      acceptedEpoch: 1,
    );

    final results = <Result<Object?>>[
      await crypto.probeIncomingTransport(empty),
      await crypto.prepareCreate(
        GroupCreationIntent(
          creatorUserId: ownerId,
          creatorDeviceId: ownerDeviceId,
          metadata: const GroupMetadata(name: 'closed'),
          members: [owner],
          createdMs: 0,
        ),
      ),
      await crypto.inspectIncomingWelcome(
        mlsObject: empty,
        localUserId: ownerId,
        localDeviceId: ownerDeviceId,
      ),
      await crypto.prepareControl(
        current: state,
        currentOpaqueMlsState: empty,
        operation: const LeaveGroupOperation(),
        actorUserId: ownerId,
        actorDeviceId: ownerDeviceId,
        createdMs: 0,
      ),
      await crypto.inspectIncomingControl(
        current: state,
        currentOpaqueMlsState: empty,
        mlsObject: empty,
        localUserId: ownerId,
        localDeviceId: ownerDeviceId,
      ),
      await crypto.prepareApplicationMessage(
        current: state,
        currentOpaqueMlsState: empty,
        senderUserId: ownerId,
        senderDeviceId: ownerDeviceId,
        text: 'closed',
        createdMs: 0,
      ),
      await crypto.inspectIncomingApplication(
        current: state,
        currentOpaqueMlsState: empty,
        mlsObject: empty,
        localUserId: ownerId,
        localDeviceId: ownerDeviceId,
      ),
      await crypto.generateKeyPackages(
        MlsKeyPackageGenerationRequest(
          opaqueDeviceState: Uint8List(64),
          migrationUnixDay: 0,
          localVerifiedBundleRequest: Uint8List(64),
          count: 1,
          kind: MlsKeyPackageKind.lastResort,
        ),
      ),
      await crypto.reconcileFork(
        current: state,
        currentOpaqueMlsState: empty,
        siblingCommits: const [],
        localUserId: ownerId,
        localDeviceId: ownerDeviceId,
      ),
    ];

    expect(results, hasLength(9));
    for (final result in results) {
      expect(
        result,
        isA<FailureResult<Object?>>().having(
          (value) => value.failure,
          'failure',
          const UnsupportedProtocolFailure(
            UnsupportedProtocolFailureKind.capability,
          ),
        ),
      );
    }
  });
}
