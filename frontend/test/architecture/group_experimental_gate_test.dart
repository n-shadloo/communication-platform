import 'dart:io';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/group_providers.dart';
import 'package:communication_platform/features/groups/infrastructure/unsupported_group_mls.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ADR-055: the closed-beta group surface is withheld from the distributed
/// artifact until the packaged native core it calls has been observed running
/// on hardware.
///
/// These assertions cover the two halves that have to stay true together. The
/// gate must be closed and must be the *kind* of thing that cannot be opened at
/// runtime; and with it closed, nothing of the group stack may be reachable —
/// not the screens, not the crypto, not the KeyPackage upload, and not the
/// inbound path. A surface that is merely hidden from view is not withheld.
void main() {
  ProviderContainer containerFor(AppEnvironment environment) {
    final container = ProviderContainer(
      overrides: [appEnvironmentProvider.overrideWithValue(environment)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the ledger is empty and says so', () {
    test('no cell of the packaged-core matrix has evidence', () {
      expect(GroupExperimentalGate.ledger.evidence, isEmpty);
      expect(GroupExperimentalGate.ledger.isOpen, isFalse);
      expect(
        GroupExperimentalGate.ledger.outstanding,
        containsAll(<GroupMlsFieldCell>[
          GroupMlsFieldCell.arm64V8a,
          GroupMlsFieldCell.armeabiV7a,
        ]),
      );
    });

    test('the mandatory cells are the ABIs a recipient can actually load', () {
      // x86_64 is packaged but reached in practice only by an emulator, and an
      // emulated record is inadmissible - so requiring it could only ever be
      // satisfied by hardware nobody in this deployment has.
      expect(GroupMlsFieldCell.arm64V8a.mandatory, isTrue);
      expect(GroupMlsFieldCell.armeabiV7a.mandatory, isTrue);
      expect(GroupMlsFieldCell.x8664.mandatory, isFalse);
      expect(GroupMlsFieldCell.arm64V8a.abi, 'arm64-v8a');
      expect(GroupMlsFieldCell.armeabiV7a.abi, 'armeabi-v7a');
    });

    test('the run-record directory documents the closed state', () {
      final readme = File(
        'docs/validation/beta-mls-core/README.md',
      ).readAsStringSync();
      expect(readme, contains('Gate state: CLOSED'));
      expect(
        Directory(
          'docs/validation/beta-mls-core',
        ).listSync().whereType<Directory>(),
        isEmpty,
        reason:
            'A run directory here without a matching admissible ledger entry '
            'means evidence was produced and never read.',
      );
    });
  });

  group('the gate cannot be opened at runtime', () {
    final source = File(
      'lib/app/config/group_production_gate.dart',
    ).readAsStringSync();

    test('there is no define, no remote value and no setter', () {
      expect(source, isNot(contains('bool.fromEnvironment')));
      expect(source, isNot(contains('String.fromEnvironment')));
      expect(source, isNot(contains('int.fromEnvironment')));
      expect(source, contains('static const ledger'));
      // `forEvidence` exists so a test can prove the mechanism rather than only
      // that the real ledger is empty. It must stay test-only, and the
      // application must read the constant and nothing else.
      expect(source, contains('@visibleForTesting'));
      for (final consumer in const [
        'lib/app/dependencies/group_providers.dart',
        'lib/app/dependencies/sync_providers.dart',
        'lib/features/groups/presentation/group_pages.dart',
        'lib/features/contacts/presentation/contact_pages.dart',
      ]) {
        expect(
          File(consumer).readAsStringSync(),
          isNot(contains('forEvidence')),
          reason: '$consumer must not be able to supply its own ledger',
        );
      }
    });

    test('the permit still requires the beta environment as well', () {
      // Evidence is necessary and not sufficient. If the ledger ever opens, the
      // environment test is what keeps production out - production has no beta
      // symbol to call and must never resolve a permit even so.
      expect(source, contains('environment == AppEnvironment.beta'));
      expect(
        GroupExperimentalGate.forEvidence(_fullLedger).isOpen,
        isTrue,
        reason: 'the mechanism must work, or the empty ledger proves nothing',
      );
    });
  });

  group('admissibility refuses the ways a ledger becomes decoration', () {
    test('a complete record on hardware is admissible', () {
      expect(_evidence().isAdmissible, isTrue);
    });

    test('an emulator record never counts', () {
      expect(_evidence(emulated: true).isAdmissible, isFalse);
      expect(
        GroupExperimentalGate.forEvidence([
          _evidence(emulated: true),
          _evidence(cell: GroupMlsFieldCell.armeabiV7a, emulated: true),
        ]).isOpen,
        isFalse,
      );
    });

    test('a run that skipped any operation of the round trip never counts', () {
      for (final skipped in GroupMlsExercisedOperation.values) {
        final partial = GroupMlsExercisedOperation.values
            .where((operation) => operation != skipped)
            .toList(growable: false);
        expect(
          _evidence(operations: partial).isAdmissible,
          isFalse,
          reason: 'a record missing $skipped opened a cell',
        );
      }
    });

    test('a row with nothing behind it never counts', () {
      expect(_evidence(hardware: '  ').isAdmissible, isFalse);
      expect(_evidence(platformVersion: '').isAdmissible, isFalse);
      expect(_evidence(runRecord: '   ').isAdmissible, isFalse);
    });

    test('a date nobody could have observed on never counts', () {
      for (final date in const [
        '2026-13-45',
        '2026-02-30',
        '26-08-24',
        '2026-8-24',
        'yesterday',
        '',
      ]) {
        expect(
          _evidence(observedOn: date).isAdmissible,
          isFalse,
          reason: '$date was accepted as a date',
        );
      }
    });

    test('a partially satisfied matrix opens nothing', () {
      expect(
        GroupExperimentalGate.forEvidence([_evidence()]).isOpen,
        isFalse,
        reason: 'one APK carries every ABI and the installer picks one',
      );
    });
  });

  group('with the gate closed the surface is withheld in substance', () {
    test('the beta artifact holds no permit', () {
      expect(
        GroupProductionGate.privateExperimentalPermit(AppEnvironment.beta),
        isNull,
      );
      expect(
        GroupProductionGate.privateExperimentalWithheld(AppEnvironment.beta),
        isTrue,
      );
    });

    test('availability is withheld, and withheld is not available', () {
      expect(
        containerFor(
          AppEnvironment.beta,
        ).read(groupFeatureAvailabilityProvider),
        GroupFeatureAvailability.privateExperimentalWithheld,
      );
      expect(
        GroupFeatureAvailability.privateExperimentalWithheld.isAvailable,
        isFalse,
      );
    });

    test('no MLS stack is composed', () {
      final container = containerFor(AppEnvironment.beta);
      expect(
        container.read(groupMlsCryptoProvider),
        isA<UnsupportedGroupMlsCrypto>(),
      );
      expect(
        container.read(fullyComposedGroupMlsCryptoProvider.future),
        completion(isA<UnsupportedGroupMlsCrypto>()),
        reason:
            'the fully composed provider is what the inbound coordinator and '
            'the use cases actually read',
      );
    });

    test('no KeyPackage is generated or uploaded', () {
      // This is the half that makes the difference between withheld and hidden.
      // A build that closes its screens while still publishing KeyPackages
      // advertises to the backend and to every peer a capability it will not
      // honour - the mirror image of the defect ADR-044 fixed.
      expect(
        containerFor(AppEnvironment.beta).read(
          groupKeyPackageMaintenanceServiceProvider((
            userId: '11111111-1111-4111-8111-111111111111',
            deviceId: '22222222-2222-4222-8222-222222222222',
          )).future,
        ),
        throwsStateError,
      );
    });

    test('no screen can be reached around the gate', () {
      // Every group page checks availability before it checks anything else,
      // including its own injected-collaborator path. That ordering used to be
      // the other way round on three of them, so a caller supplying its own
      // collaborators rendered the flow in a build that has no group stack.
      // Nothing in the router does that, and a gate a constructor argument can
      // bypass is still not a gate.
      final screens = File(
        'lib/features/groups/presentation/group_pages.dart',
      ).readAsStringSync();
      const gate =
          'if (!ref.watch(groupFeatureAvailabilityProvider).isAvailable) {';
      final gateCount = gate.allMatches(screens).length;
      expect(gateCount, 5, reason: 'one gate per routed group screen');
      for (final injection in const [
        'if (injectedContacts != null && onCreate != null) {',
        'if (injectedState != null && injectedMessages != null && '
            'onSend != null) {',
        'if (injectedState != null && onMutate != null) {',
      ]) {
        final injectionAt = screens.indexOf(injection);
        expect(injectionAt, greaterThan(-1), reason: 'missing: $injection');
        final gateBefore = screens.lastIndexOf(gate, injectionAt);
        expect(
          gateBefore,
          greaterThan(-1),
          reason: 'no availability gate precedes: $injection',
        );
        // The gate must be the immediately preceding statement, not one that
        // happens to appear earlier in another widget's build method.
        expect(
          screens.substring(gateBefore, injectionAt),
          isNot(contains('Widget build(')),
          reason: 'the gate preceding $injection belongs to another widget',
        );
      }
    });

    test('the durable sync engine composes no KeyPackage maintenance', () {
      // `sync_providers.dart` reaches the maintenance service only through the
      // permit, so a withheld build must leave that post-inbox work out
      // entirely rather than construct it and decline to run it.
      final source = File(
        'lib/app/dependencies/sync_providers.dart',
      ).readAsStringSync();
      expect(source, contains('GroupProductionGate.privateExperimentalPermit'));
      expect(
        source,
        contains('if (groupKeyPackageMaintenance != null)'),
        reason: 'the null permit must remove the work, not disable it',
      );
    });
  });

  group('production is unchanged by any of this', () {
    test('production is unavailable, and for its own reason', () {
      expect(
        GroupProductionGate.privateExperimentalWithheld(
          AppEnvironment.production,
        ),
        isFalse,
        reason:
            'production has no group stack to withhold and says so in '
            'different words',
      );
      expect(
        containerFor(
          AppEnvironment.production,
        ).read(groupFeatureAvailabilityProvider),
        GroupFeatureAvailability.productionUnavailable,
      );
    });

    test('the production transport assertion is untouched', () {
      expect(
        GroupProductionGate.releaseAssertion.productionTransportEnabled,
        isFalse,
      );
      expect(
        File('lib/main_production.dart').readAsStringSync(),
        contains('GroupProductionGate.releaseAssertion'),
      );
    });

    test('a full ledger would still leave production closed', () {
      // The evidence gate is in front of the beta boundary, never in place of
      // it. If every cell were satisfied tomorrow, production would still hold
      // no permit and still resolve the unsupported adapter.
      expect(GroupExperimentalGate.forEvidence(_fullLedger).isOpen, isTrue);
      expect(
        GroupProductionGate.privateExperimentalPermit(
          AppEnvironment.production,
        ),
        isNull,
      );
    });
  });
}

GroupMlsFieldEvidence _evidence({
  GroupMlsFieldCell cell = GroupMlsFieldCell.arm64V8a,
  String hardware = 'samsung SM-A566B',
  String platformVersion = 'Android 16 (API 36)',
  String observedOn = '2026-08-24',
  bool emulated = false,
  List<GroupMlsExercisedOperation>? operations,
  String runRecord = 'docs/validation/beta-mls-core/example/run.json',
}) => GroupMlsFieldEvidence(
  cell: cell,
  hardware: hardware,
  platformVersion: platformVersion,
  observedOn: observedOn,
  emulated: emulated,
  operations: operations ?? GroupMlsExercisedOperation.values,
  runRecord: runRecord,
);

final _fullLedger = <GroupMlsFieldEvidence>[
  _evidence(),
  _evidence(cell: GroupMlsFieldCell.armeabiV7a),
];
