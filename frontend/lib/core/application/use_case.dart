import 'package:communication_platform/core/result/result.dart';

/// The only entry point a presentation command uses to invoke application logic.
abstract interface class UseCase<Output, Input> {
  Future<Result<Output>> execute(Input input);
}

/// Explicit input type for use cases that do not require command data.
final class NoInput {
  const NoInput();
}
