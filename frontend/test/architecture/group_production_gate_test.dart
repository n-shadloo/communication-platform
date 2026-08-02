import 'dart:io';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/group_providers.dart';
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
}
