/// Marker for immutable facts emitted by application behavior.
///
/// Concrete event types live with the feature that owns their meaning. Durable events
/// are persisted by repository adapters before presentation observes their projections.
abstract interface class ApplicationEvent {
  const ApplicationEvent();
}
