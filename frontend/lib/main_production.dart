import 'package:communication_platform/app/bootstrap.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';

const _pqMlsReleaseGate = GroupProductionGate.releaseAssertion;

Future<void> main() {
  // Referencing the const makes a gate change fail during release compilation.
  if (_pqMlsReleaseGate.productionTransportEnabled) {
    throw StateError('PQ MLS production gate is closed.');
  }
  return bootstrap(AppEnvironment.production);
}
