/// Marker for typed requests entering the application layer.
///
/// A feature owns its concrete commands. Cross-feature code exchanges these contracts
/// through use cases or ports rather than reaching into another feature's providers.
abstract interface class ApplicationCommand {
  const ApplicationCommand();
}
