import 'package:communication_platform/app/bootstrap.dart';
import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/dependencies/deferred_delivery_catch_up.dart';

Future<void> main() => bootstrap(AppEnvironment.beta);

/// The headless entry point the platform runs for a deferred catch-up.
///
/// One per flavor, deliberately. The compiled environment is what decides the
/// provisioned server, the trust anchor and the closed-beta group permit, and
/// this repository holds that it must be fixed by the entry point rather than
/// selectable at runtime — so the platform picks a *name*, and which
/// `AppEnvironment` that name resolves to is decided by which file was
/// compiled. A build asked for an entry point it does not contain fails to
/// start one, which is the fail-closed direction.
@pragma('vm:entry-point')
Future<void> backgroundDelivery() =>
    runDeferredDeliveryEntryPoint(AppEnvironment.beta);
