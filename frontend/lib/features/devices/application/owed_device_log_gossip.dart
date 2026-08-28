import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/result.dart';

/// How long an advertisement to one peer stands for the next one owed to them.
///
/// A device-log head moves when a device is enrolled, revoked or rotates a
/// prekey — events measured in days. Advertising the same heads to the same
/// person twice inside a minute therefore tells them nothing they were not
/// already told, while costing a full fan-out: a device lookup, a ratchet step
/// per device and a commit transaction. This is what makes two sends to one
/// peer in quick succession produce one gossip round rather than two, when they
/// fall in different delivery cycles; inside one cycle the owed set already
/// does it.
const Duration defaultGossipCoalescingWindow = Duration(minutes: 1);

/// The peers this process still owes an advertisement of its device-log heads.
///
/// Gossip is owed to a peer, not to a message. It used to be awaited by the
/// send preparation that discovered the debt, which put a whole second fan-out
/// — its own two device lookups, its own ratchet steps, its own commit — in
/// front of a ciphertext that was already sealed and already durable. This is
/// what replaced that: the preparation records the debt and returns, and the
/// delivery cycle pays it as an ordinary unit of work, after the outbox pass
/// that carried the user's own message to the wire.
///
/// A detached future was not an option and is not one here. A delivery cycle
/// can be a headless catch-up that the platform woke for a bounded moment; that
/// entry point disposes its container and closes its database the instant
/// `synchronize()` returns, so a future still running then is a future running
/// against a closed database, or one racing whatever the next cycle opens.
/// Everything below is reached from inside the cycle, and finishes inside it.
final class OwedDeviceLogGossip {
  OwedDeviceLogGossip({
    required this.advertise,
    required this.clock,
    this.coalescingWindow = defaultGossipCoalescingWindow,
  });

  /// Runs one gossip fan-out for one peer. Its result is recorded and never
  /// propagated: see [settle].
  final Future<Result<void>> Function(String peerUserId) advertise;

  final TimeSource clock;
  final Duration coalescingWindow;

  final Set<String> _owed = {};
  final Map<String, DateTime> _advertised = {};
  Future<void>? _settling;

  /// Peers currently owed an advertisement, for tests and diagnostics.
  Set<String> get owed => Set.unmodifiable(_owed);

  /// Records that [peerUserId] is owed an advertisement.
  ///
  /// One set insertion, and nothing else. It performs no I/O, it cannot fail,
  /// it returns nothing to await and there is no path from it back to the
  /// caller's outcome — which is how "a gossip failure is not the send's
  /// failure" stops being a swallowed `catch` and starts being a shape.
  void owe(String peerUserId) {
    _owed.add(peerUserId);
  }

  /// Pays every advertisement owed when this was called.
  ///
  /// Never fails, and never reports. A peer whose fan-out failed is not
  /// re-owed here: the debt is re-created by the next send to them, which is
  /// exactly what it did before, and nothing records a success it did not have,
  /// so that next send is not suppressed either.
  ///
  /// Debts incurred *during* a drain are left for the next one rather than
  /// extended onto this one, so this terminates against any rate of arrival.
  /// Concurrent calls join the drain in progress, which is what keeps one
  /// cycle's settlement from overlapping the next one's.
  Future<void> settle() {
    final active = _settling;
    if (active != null) {
      return active;
    }
    final run = _drain();
    _settling = run;
    return run.whenComplete(() {
      if (identical(_settling, run)) {
        _settling = null;
      }
    });
  }

  Future<void> _drain() async {
    final due = _owed.toList(growable: false);
    _owed.clear();
    for (final peerUserId in due) {
      final now = clock.now();
      final last = _advertised[peerUserId];
      if (last != null && now.difference(last) < coalescingWindow) {
        continue;
      }
      try {
        final advertised = await advertise(peerUserId);
        if (advertised is Success<void>) {
          _advertised[peerUserId] = now;
        }
      } on Object {
        // A fan-out this device could not perform is not a fact about the send
        // that owed it, and there is nothing here to report it to. The next
        // send to this peer owes it again.
      }
    }
  }
}
