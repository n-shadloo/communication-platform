import 'package:communication_platform/core/domain/value_object.dart';

/// Base contract for a domain object with a value-object identity.
abstract interface class Entity<Id extends ValueObject> {
  Id get id;
}
