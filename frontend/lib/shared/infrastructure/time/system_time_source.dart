import 'package:communication_platform/core/application/ports/time_source.dart';

/// Default runtime adapter. Tests replace this port through a ProviderScope override.
final class SystemTimeSource implements TimeSource {
  const SystemTimeSource();

  @override
  DateTime now() => DateTime.now().toUtc();
}
