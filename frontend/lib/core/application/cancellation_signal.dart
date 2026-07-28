import 'dart:async';

/// Framework-free cancellation shared by application use cases and adapters.
final class CancellationSignal {
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;
  Stream<void> get whenCancelled => _controller.stream;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _controller.add(null);
    unawaited(_controller.close());
  }
}
