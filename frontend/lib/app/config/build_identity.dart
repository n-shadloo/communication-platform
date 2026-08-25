/// What this build calls itself, for the one surface that has to say so.
///
/// Kept as a compile-time constant rather than read from the package manifest
/// at runtime: reading it would mean a plugin, and ADR-054 decided this
/// artifact's outside dependencies point by point. `test/architecture` pins it
/// to `pubspec.yaml`, so the two cannot drift apart silently.
abstract final class BuildIdentity {
  /// Exactly the `version:` line of `pubspec.yaml`, semantic version and build
  /// number included.
  static const version = '0.1.0+1';
}
