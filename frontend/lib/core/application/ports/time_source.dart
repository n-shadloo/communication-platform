import 'package:communication_platform/core/application/ports/port.dart';

/// Supplies time to use cases without binding them to a platform clock.
abstract interface class TimeSource implements Port {
  DateTime now();
}
