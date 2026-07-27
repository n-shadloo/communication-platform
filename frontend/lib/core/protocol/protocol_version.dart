import 'package:communication_platform/core/domain/value_object.dart';

/// Version metadata for client-owned protocol payloads.
///
/// Parsing, cryptography, and transport belong in later protocol implementations.
final class ProtocolVersion extends ValueObject {
  const ProtocolVersion({required this.major, required this.minor})
    : assert(major >= 0),
      assert(minor >= 0);

  final int major;
  final int minor;

  @override
  List<Object?> get equalityComponents => [major, minor];
}
