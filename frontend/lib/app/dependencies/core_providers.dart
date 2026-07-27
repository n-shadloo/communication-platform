import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/shared/infrastructure/time/system_time_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dependency descriptors are immutable. Their instances are owned by ProviderScope,
/// which lets tests and app roots provide isolated overrides without global mutation.
final timeSourceProvider = Provider<TimeSource>(
  (ref) => const SystemTimeSource(),
);
