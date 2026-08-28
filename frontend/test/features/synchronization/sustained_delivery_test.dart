import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:communication_platform/features/synchronization/application/ports/sustained_delivery_ports.dart';
import 'package:communication_platform/features/synchronization/application/sustained_delivery.dart';
import 'package:communication_platform/features/synchronization/domain/sustained_delivery_model.dart';
import 'package:communication_platform/features/synchronization/infrastructure/drift_sustained_delivery_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything about the opt-in capability that can be decided without a device.
///
/// The Kotlin half cannot be exercised here and no device is available, so what
/// is proven is the whole of the *policy*: when it may run, what it asks for and
/// in what order, what it concludes from every answer, and — most importantly —
/// that every path except one leaves the application exactly as it found it.
void main() {
  group('the off state', () {
    test(
      'nothing runs, nothing is asked for, and nothing is recorded',
      () async {
        final platform = FakeSustainedPlatform();
        final store = InMemorySustainedStore();

        final status = await ReconcileSustainedDelivery(
          platform: platform,
          store: store,
        ).call();

        expect(status, SustainedDeliveryStatus.off);
        expect(platform.starts, 0);
        expect(platform.stops, 0);
        expect(platform.exemptionRequests, 0);
        expect(platform.running, isFalse);
        expect(store.written, isEmpty, reason: 'off leaves no durable trace');
      },
    );

    test(
      'a build with no implementation says so and asks for nothing',
      () async {
        final platform = FakeSustainedPlatform(supported: false);
        final store = InMemorySustainedStore();

        expect(
          await ReconcileSustainedDelivery(
            platform: platform,
            store: store,
          ).call(),
          SustainedDeliveryStatus.unavailable,
        );
        final outcome = await EnableSustainedDelivery(
          platform: platform,
          store: store,
          alerts: FakeAlertGate(grants: true),
        ).call();
        expect(
          outcome,
          isA<SustainedDeliveryRefused>().having(
            (refused) => refused.refusal,
            'refusal',
            SustainedDeliveryRefusal.unavailable,
          ),
        );
        expect(platform.exemptionRequests, 0);
        expect(store.written, isEmpty);
      },
    );

    test(
      'a recorded choice is never inferred from storage that cannot be read',
      () async {
        // The dangerous direction: a database that will not open must not be
        // read as consent. It is read as *off*, so an unreadable device starts
        // no service and displays nothing.
        final platform = FakeSustainedPlatform(exempt: true);
        final status = await ReconcileSustainedDelivery(
          platform: platform,
          store: UnreadableSustainedStore(),
        ).call();

        expect(status, SustainedDeliveryStatus.off);
        expect(platform.starts, 0);
      },
    );
  });

  group('turning it on', () {
    test('asks in order, records the choice, then starts the service', () async {
      final order = <String>[];
      final platform = FakeSustainedPlatform(
        grantsExemption: true,
        order: order,
      );
      final store = InMemorySustainedStore(order: order);
      final alerts = FakeAlertGate(
        grants: true,
        platform: platform,
        order: order,
      );

      final outcome = await EnableSustainedDelivery(
        platform: platform,
        store: store,
        alerts: alerts,
      ).call();

      expect(outcome, isA<SustainedDeliveryEnabled>());
      expect(alerts.requests, 1);
      expect(platform.exemptionRequests, 1);
      expect(store.enabled, isTrue);
      expect(platform.running, isTrue);
      // Recorded before started, so that what is stored and what is running can
      // never disagree if the process dies between the two.
      expect(order, ['alerts', 'exemption', 'record', 'start']);
      expect(
        platform.state.statusFor(chosen: true),
        SustainedDeliveryStatus.holding,
      );
    });

    test('asks for nothing it already has', () async {
      final platform = FakeSustainedPlatform(alertsEnabled: true, exempt: true);
      final alerts = FakeAlertGate(grants: true);

      await EnableSustainedDelivery(
        platform: platform,
        store: InMemorySustainedStore(),
        alerts: alerts,
      ).call();

      expect(alerts.requests, 0);
      expect(platform.exemptionRequests, 0);
      expect(platform.running, isTrue);
    });
  });

  group('every refusal fails closed', () {
    test('notifications refused: nothing else is even asked', () async {
      final platform = FakeSustainedPlatform();
      final store = InMemorySustainedStore();

      final outcome = await EnableSustainedDelivery(
        platform: platform,
        store: store,
        alerts: FakeAlertGate(grants: false),
      ).call();

      expect(refusalOf(outcome), SustainedDeliveryRefusal.alertsRefused);
      expect(
        platform.exemptionRequests,
        0,
        reason:
            'a connection held for messages nobody is told about is a battery '
            'cost with no benefit, so the harder question is never reached',
      );
      expect(platform.starts, 0);
      expect(store.written, isEmpty);
      expect(platform.running, isFalse);
    });

    test(
      'exemption refused: nothing is started and nothing is stored',
      () async {
        final platform = FakeSustainedPlatform(alertsEnabled: true);
        final store = InMemorySustainedStore();

        final outcome = await EnableSustainedDelivery(
          platform: platform,
          store: store,
          alerts: FakeAlertGate(grants: true),
        ).call();

        expect(refusalOf(outcome), SustainedDeliveryRefusal.exemptionRefused);
        expect(platform.exemptionRequests, 1);
        expect(platform.starts, 0);
        expect(store.written, isEmpty);
      },
    );

    test('the choice cannot be recorded: nothing is started', () async {
      // A capability that is on until the next launch and then silently off is
      // worse than one that never started, so this refuses rather than running
      // without a durable choice behind it.
      final platform = FakeSustainedPlatform(alertsEnabled: true, exempt: true);

      final outcome = await EnableSustainedDelivery(
        platform: platform,
        store: UnwritableSustainedStore(),
        alerts: FakeAlertGate(grants: true),
      ).call();

      expect(refusalOf(outcome), SustainedDeliveryRefusal.notRecorded);
      expect(platform.starts, 0);
      expect(platform.running, isFalse);
    });

    test(
      'the platform refuses to start it: the choice is withdrawn again',
      () async {
        // The manufacturer-restriction case among others. Leaving the choice
        // recorded would mean a later launch silently retrying what the user
        // was just told had failed.
        final platform = FakeSustainedPlatform(
          alertsEnabled: true,
          exempt: true,
          refusesToStart: true,
        );
        final store = InMemorySustainedStore();

        final outcome = await EnableSustainedDelivery(
          platform: platform,
          store: store,
          alerts: FakeAlertGate(grants: true),
        ).call();

        expect(refusalOf(outcome), SustainedDeliveryRefusal.platformRefused);
        expect(store.enabled, isFalse);
        expect(platform.running, isFalse);
        expect(
          await ReconcileSustainedDelivery(
            platform: platform,
            store: store,
          ).call(),
          SustainedDeliveryStatus.off,
          reason:
              'a refused enable leaves nothing for a later launch to resume',
        );
      },
    );
  });

  group('turning it off returns to a clean off state', () {
    test('the service stops and the choice is deleted, not falsified', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSustainedDeliveryStore(database);
      final platform = FakeSustainedPlatform(alertsEnabled: true, exempt: true);

      await EnableSustainedDelivery(
        platform: platform,
        store: store,
        alerts: FakeAlertGate(grants: true),
      ).call();
      expect(platform.running, isTrue);
      expect((await store.readEnabled() as Success<bool>).value, isTrue);
      expect(await rowCount(database), 1);

      final status = await DisableSustainedDelivery(
        platform: platform,
        store: store,
      ).call();

      expect(status, SustainedDeliveryStatus.off);
      expect(platform.running, isFalse);
      expect((await store.readEnabled() as Success<bool>).value, isFalse);
      expect(
        await rowCount(database),
        0,
        reason:
            'an installation that never turned it on and one that turned it on '
            'and off again must be indistinguishable on disk',
      );
    });

    test('a later reconciliation starts nothing', () async {
      final platform = FakeSustainedPlatform(alertsEnabled: true, exempt: true);
      final store = InMemorySustainedStore();
      await EnableSustainedDelivery(
        platform: platform,
        store: store,
        alerts: FakeAlertGate(grants: true),
      ).call();
      await DisableSustainedDelivery(platform: platform, store: store).call();

      final startsAfterDisable = platform.starts;
      expect(
        await ReconcileSustainedDelivery(
          platform: platform,
          store: store,
        ).call(),
        SustainedDeliveryStatus.off,
      );
      expect(platform.starts, startsAfterDisable);
      expect(platform.running, isFalse);
    });
  });

  group('reconciliation reports what is true and makes it true', () {
    test(
      'a stopped service is started again without asking anything',
      () async {
        final platform = FakeSustainedPlatform(
          alertsEnabled: true,
          exempt: true,
        );
        final store = InMemorySustainedStore(enabled: true);

        final status = await ReconcileSustainedDelivery(
          platform: platform,
          store: store,
        ).call();

        expect(status, SustainedDeliveryStatus.holding);
        expect(platform.running, isTrue);
        expect(
          platform.exemptionRequests,
          0,
          reason: 'a restore that showed a dialog would interrogate on launch',
        );
      },
    );

    test(
      'a withdrawn exemption is reported, and the service is stopped with it',
      () async {
        final platform = FakeSustainedPlatform(
          alertsEnabled: true,
          exempt: true,
        );
        final store = InMemorySustainedStore(enabled: true);
        await ReconcileSustainedDelivery(
          platform: platform,
          store: store,
        ).call();
        expect(platform.running, isTrue);

        // A phone update, or the user in system settings. Neither tells this
        // application anything, which is why the answer is re-read rather than
        // remembered.
        platform.exempt = false;

        expect(
          await ReconcileSustainedDelivery(
            platform: platform,
            store: store,
          ).call(),
          SustainedDeliveryStatus.exemptionWithdrawn,
        );
        expect(
          platform.running,
          isFalse,
          reason:
              'a service kept alive for a connection this will not hold is '
              'battery spent and a permanent entry displayed for nothing',
        );
        expect(
          store.enabled,
          isTrue,
          reason: 'the choice is theirs, not the phone’s',
        );
      },
    );

    test('withdrawn notifications are reported the same way', () async {
      final platform = FakeSustainedPlatform(alertsEnabled: true, exempt: true);
      final store = InMemorySustainedStore(enabled: true);
      await ReconcileSustainedDelivery(platform: platform, store: store).call();

      platform.alertsEnabled = false;

      expect(
        await ReconcileSustainedDelivery(
          platform: platform,
          store: store,
        ).call(),
        SustainedDeliveryStatus.alertsWithheld,
      );
      expect(platform.running, isFalse);
    });

    test('only the complete arrangement holds the connection', () {
      const holding = SustainedDeliveryStatus.holding;
      expect(holding.holdsConnection, isTrue);
      for (final status in SustainedDeliveryStatus.values) {
        if (status != holding) {
          expect(
            status.holdsConnection,
            isFalse,
            reason:
                '$status means the thing that keeps this process out of the '
                'cached state is not doing so, and a socket held anyway is one '
                'the platform closes',
          );
        }
      }
    });
  });

  group('the durable choice', () {
    test('survives a re-read and reports nothing when absent', () async {
      final database = LocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = DriftSustainedDeliveryStore(database);

      expect((await store.readEnabled() as Success<bool>).value, isFalse);
      expect(await store.writeEnabled(enabled: true), isA<Success<void>>());
      expect((await store.readEnabled() as Success<bool>).value, isTrue);
      // Written twice, because a preference that could only be written once
      // would fail the second time the user changed their mind.
      expect(await store.writeEnabled(enabled: true), isA<Success<void>>());
      expect((await store.readEnabled() as Success<bool>).value, isTrue);
    });
  });
}

SustainedDeliveryRefusal? refusalOf(SustainedDeliveryEnableOutcome outcome) =>
    outcome is SustainedDeliveryRefused ? outcome.refusal : null;

Future<int> rowCount(LocalDatabase database) async =>
    (await (database.select(database.localPreferences)..where(
              (entry) => entry.preferenceKey.equals(
                DriftSustainedDeliveryStore.enabledKey,
              ),
            ))
            .get())
        .length;

/// The platform, as a host test can hold it: every answer is a fact the fake
/// records, and every action is observable.
final class FakeSustainedPlatform implements SustainedDeliveryPlatformPort {
  FakeSustainedPlatform({
    this.supported = true,
    this.alertsEnabled = false,
    this.exempt = false,
    this.grantsExemption = false,
    this.refusesToStart = false,
    List<String>? order,
  }) : order = order ?? <String>[];

  final bool supported;
  bool alertsEnabled;
  bool exempt;

  /// What the user does in the system dialog. The dialog itself reports
  /// refusal and dismissal identically, which is why the real port re-reads
  /// `isIgnoringBatteryOptimizations()` afterwards and why this fake changes
  /// the state rather than the return value.
  final bool grantsExemption;
  bool refusesToStart;
  bool running = false;
  int starts = 0;
  int stops = 0;
  int exemptionRequests = 0;
  int vendorScreens = 0;

  /// The sequence the whole flow performed, shared with the other fakes, so
  /// that "asks in order" is a statement about the order and not about three
  /// separate counters.
  final List<String> order;

  SustainedDeliveryPlatformState get state => SustainedDeliveryPlatformState(
    supported: supported,
    running: running,
    exempt: exempt,
    alertsEnabled: alertsEnabled,
  );

  @override
  Future<SustainedDeliveryPlatformState?> platformState() async =>
      supported ? state : null;

  @override
  Future<SustainedDeliveryPlatformState?> requestExemption() async {
    exemptionRequests += 1;
    order.add('exemption');
    if (grantsExemption) {
      exempt = true;
    }
    return supported ? state : null;
  }

  @override
  Future<SustainedDeliveryPlatformState?> start() async {
    starts += 1;
    order.add('start');
    if (!supported) {
      return null;
    }
    running = !refusesToStart;
    return state;
  }

  @override
  Future<SustainedDeliveryPlatformState?> stop() async {
    stops += 1;
    if (!supported) {
      return null;
    }
    running = false;
    return state;
  }

  @override
  Future<void> openVendorSettings() async {
    vendorScreens += 1;
  }
}

final class FakeAlertGate implements SustainedDeliveryAlertGate {
  FakeAlertGate({required this.grants, this.platform, List<String>? order})
    : order = order ?? <String>[];

  final bool grants;

  /// Granting the permission is what changes the platform's own answer, which
  /// is what the flow re-reads. A gate that returned true without changing it
  /// would be testing a device that does not exist.
  final FakeSustainedPlatform? platform;
  final List<String> order;
  int requests = 0;

  @override
  Future<bool> ensureAlertsEnabled() async {
    requests += 1;
    order.add('alerts');
    if (grants) {
      platform?.alertsEnabled = true;
    }
    return grants;
  }
}

final class InMemorySustainedStore implements SustainedDeliveryStorePort {
  InMemorySustainedStore({this.enabled = false, List<String>? order})
    : order = order ?? <String>[];

  bool enabled;
  final List<String> order;
  final List<bool> written = [];

  @override
  Future<Result<bool>> readEnabled() async => Result.success(enabled);

  @override
  Future<Result<void>> writeEnabled({required bool enabled}) async {
    this.enabled = enabled;
    written.add(enabled);
    if (enabled) {
      order.add('record');
    }
    return const Result.success(null);
  }
}

final class UnreadableSustainedStore implements SustainedDeliveryStorePort {
  @override
  Future<Result<bool>> readEnabled() async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));

  @override
  Future<Result<void>> writeEnabled({required bool enabled}) async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));
}

final class UnwritableSustainedStore implements SustainedDeliveryStorePort {
  @override
  Future<Result<bool>> readEnabled() async => const Result.success(false);

  @override
  Future<Result<void>> writeEnabled({required bool enabled}) async =>
      const Result.failure(StorageFailure(StorageFailureKind.unavailable));
}
