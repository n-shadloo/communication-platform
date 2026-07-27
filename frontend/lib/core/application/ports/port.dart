/// Marker for an outward-facing application dependency.
///
/// Ports are declared by the application layer and implemented by infrastructure.
abstract interface class Port {
  const Port();
}

/// Marker for ports that provide access to durable application-owned state.
abstract interface class RepositoryPort implements Port {
  const RepositoryPort();
}
